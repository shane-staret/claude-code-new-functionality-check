#!/usr/bin/env bash
# install.sh — install or update the claude-code-new-functionality-check package.
#
# Copies the skill (this folder), its two agents, the reminder hook and the four
# offline test suites from the package into a Claude Code config folder. It is a
# dry run by default: it reports every step and changes nothing until --yes.
#
# Usage: install.sh [--yes] [--register-reminder] [--opt-in] [--target <dir>]
#   --yes                carry the steps out (without it, only report them)
#   --register-reminder  add the weekly reminder hook to <target>/settings.json (needs jq)
#   --opt-in             make this machine the sweeper: create the ledger folder and a
#                        denylist template (web research stays blocked until you add terms)
#   --target <dir>       the config folder (default: $CLAUDE_CONFIG_DIR, else ~/.claude)
#   -h, --help           this text
#
# Safety: it never deletes anything. A file that differs from the package is copied to
# <target>/backups/claude-code-new-functionality-check-install/<UTC>.<random>/ before it
# is replaced, an identical file is skipped, and a file the package does not ship is
# reported and left alone. Run from inside its own target, it copies nothing.
# resources/wiring.md describes every step for wiring by hand.
#
# Exit: 0 ok · 1 usage or precondition (nothing was changed) · 2 a step failed
# Env: NEW_FUNCTIONALITY_CHECK_JQ=path   the jq to use (tests)
# bash-3.2-safe.

set -uo pipefail

NAME="claude-code-new-functionality-check"
REMINDER="$NAME-reminder.sh"
REMINDER_STATUS_MESSAGE="Checking Claude Code release freshness..."
BACKUP_SUBDIR="backups/$NAME-install"
MAX_LINK_HOPS=40
PRIVATE_UMASK=077    # the ledger folder (0700) and the denylist (0600) hold private names
EXIT_USAGE=1
EXIT_FAILED=2
FIXED_FILES="agents/$NAME-evaluator.md
agents/$NAME-researcher.md
hooks/$REMINDER
hooks/tests/test-$NAME-helper.sh
hooks/tests/test-$NAME-reminder.sh
hooks/tests/test-$NAME-install.sh
hooks/tests/test-$NAME-package.sh"
# Adds one command hook to the first UserPromptSubmit group without a matcher (a group
# that runs on every prompt), or a new group when there is none. Everything else stays.
JQ_ADD_REMINDER='
def entry: {"type": "command", "command": $cmd, "statusMessage": $msg};
.hooks = (.hooks // {})
| .hooks.UserPromptSubmit = (.hooks.UserPromptSubmit // [])
| ([.hooks.UserPromptSubmit | to_entries[] | select((.value.matcher // "") == "") | .key] | first) as $i
| if $i == null then .hooks.UserPromptSubmit += [{"hooks": [entry]}]
  else .hooks.UserPromptSubmit[$i].hooks = ((.hooks.UserPromptSubmit[$i].hooks // []) + [entry]) end'
JQ_COUNT_REMINDER='[.hooks.UserPromptSubmit[]?.hooks[]? | tostring | select(contains($name))] | length'
# A settings file the entry can be added to (read with --slurp): one object whose optional hooks
# is an object, whose optional UserPromptSubmit is a list of hook groups, each with an optional
# list of hooks. Anything else is refused before a backup or a temporary file is made.
JQ_SHAPE_OK='length == 1 and (.[0]
  | type == "object"
  and ((.hooks // {}) | type == "object")
  and ((.hooks.UserPromptSubmit // []) | type == "array")
  and all((.hooks.UserPromptSubmit // [])[]; type == "object" and ((.hooks // []) | type == "array")))'

NEWLINE='
'

JQ="${NEW_FUNCTIONALITY_CHECK_JQ:-jq}"
# Every cd below clears CDPATH: an exported CDPATH would send a relative path somewhere else and
# make cd print that folder into the captured value.
SOURCE_ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
APPLY=no
REGISTER=no
OPT_IN=no
TARGET_ARG=""
TARGET=""
BACKUP_DIR=""

die() {
    # die <exit code> <message>; once a backup was taken, it also says where the backups are
    printf 'install: %s\n' "$2" >&2
    [ -z "$BACKUP_DIR" ] || printf 'install: backups taken so far: %s\n' "$BACKUP_DIR" >&2
    exit "$1"
}
say() { printf '%s\n' "$*"; }
warn() { printf 'install: warning: %s\n' "$1" >&2; }
usage() {
    # The help is the header block from "# Usage:" to the next bare "#" line, found by those
    # markers rather than by line numbers, so the block can grow without losing a line.
    awk '/^# Usage:/ { on = 1 } on && /^#$/ { exit } on { sub(/^# ?/, ""); print }' "$0"
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --yes) APPLY=yes ;;
            --register-reminder) REGISTER=yes ;;
            --opt-in) OPT_IN=yes ;;
            --target)
                [ "$#" -ge 2 ] && [ -n "$2" ] || die "$EXIT_USAGE" "--target needs a folder"
                TARGET_ARG="$2"; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "$EXIT_USAGE" "unknown option: $1 (see --help)" ;;
        esac
        shift
    done
}

package_files() {
    # package_files -> every file the package installs, relative to the package root
    (CDPATH= cd -- "$SOURCE_ROOT" && find "skills/$NAME" -type f ! -name .DS_Store | LC_ALL=C sort)
    printf '%s\n' "$FIXED_FILES"
}

preflight() {
    local rel missing=""
    TARGET="${TARGET_ARG:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
    case "$TARGET" in
        *"$NEWLINE"*) die "$EXIT_USAGE" "the target path contains a newline, which no step can handle safely; use another folder" ;;
    esac
    [ -d "$TARGET" ] || die "$EXIT_USAGE" "no Claude Code config folder at $TARGET (start Claude Code once, or pass --target <dir>)"
    TARGET="$(CDPATH= cd -- "$TARGET" && pwd)" || die "$EXIT_USAGE" "cannot enter $TARGET"
    while IFS= read -r rel; do
        [ -f "$SOURCE_ROOT/$rel" ] || missing="$missing $rel"
    done <<EOF
skills/$NAME/SKILL.md
$FIXED_FILES
EOF
    [ -z "$missing" ] || die "$EXIT_USAGE" "the package at $SOURCE_ROOT is incomplete; missing:$missing"
    # Checked before jq: installing jq would not make this path usable in a hook command.
    case "$TARGET" in
        *'"'*|*'$'*|*'`'*|*'\'*)
            [ "$REGISTER" = no ] || die "$EXIT_USAGE" "the target path cannot be quoted safely in a hook command: $TARGET" ;;
    esac
    if [ "$REGISTER" = yes ] && ! command -v "$JQ" >/dev/null 2>&1; then
        die "$EXIT_USAGE" "--register-reminder needs jq, which was not found; install jq, or add the settings entry by hand as resources/wiring.md shows (nothing was changed)"
    fi
    local tool
    for tool in curl python3; do
        command -v "$tool" >/dev/null 2>&1 || warn "$tool was not found; the helper needs it to sweep"
    done
}

ensure_backup_dir() {
    # ensure_backup_dir -> sets BACKUP_DIR to this run's backup folder, creating it once. mktemp
    # makes the name unique (two runs in one second never share a folder) and the folder private;
    # the UTC stamp in front keeps the folders in time order.
    [ -z "$BACKUP_DIR" ] || return 0
    local base="$TARGET/$BACKUP_SUBDIR" dir
    dir="$(mkdir -p "$base" && mktemp -d "$base/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")" \
        || die "$EXIT_FAILED" "cannot create a backup folder under $base; stopped before replacing anything"
    BACKUP_DIR="$dir"
}

backup_file() {
    # backup_file <relative path> -> copies <target>/<path> into this run's backup folder
    ensure_backup_dir
    mkdir -p "$BACKUP_DIR/$(dirname "$1")" && cp -p "$TARGET/$1" "$BACKUP_DIR/$1" \
        || die "$EXIT_FAILED" "could not back up $TARGET/$1; stopped before replacing it"
}

install_file() {
    # install_file <relative path> <copy|update> -> places the package copy, backing up first
    local rel="$1" action="$2"
    [ "$action" = update ] && backup_file "$rel"
    mkdir -p "$TARGET/$(dirname "$rel")" && cp -p "$SOURCE_ROOT/$rel" "$TARGET/$rel" \
        || die "$EXIT_FAILED" "could not copy $rel into $TARGET"
    case "$rel" in *.sh) chmod +x "$TARGET/$rel" || die "$EXIT_FAILED" "could not make $rel executable" ;; esac
}

lost_exec_bit() {
    # lost_exec_bit <relative path> -> true for an installed script that is no longer executable
    case "$1" in *.sh) [ ! -x "$TARGET/$1" ] ;; *) return 1 ;; esac
}

copy_step() {
    say "Files:"
    if [ "$SOURCE_ROOT" -ef "$TARGET" ]; then
        say "  the package is already installed here ($TARGET is the folder it runs from); nothing to copy"
        return 0
    fi
    local rel action note copies=0 updates=0 modes=0 same=0 extras=0 shipped
    shipped="$(package_files)"
    while IFS= read -r rel; do
        note=""
        if [ ! -e "$TARGET/$rel" ]; then action=copy; copies=$((copies+1))
        elif ! cmp -s "$SOURCE_ROOT/$rel" "$TARGET/$rel"; then action=update; updates=$((updates+1))
        elif lost_exec_bit "$rel"; then action=mode; modes=$((modes+1)); note="  (content unchanged; not executable)"
        else action=same; same=$((same+1)); fi
        printf '  %-7s %s%s\n' "$action" "$rel" "$note"
        [ "$APPLY" = yes ] || continue
        case "$action" in
            copy|update) install_file "$rel" "$action" ;;
            mode) chmod +x "$TARGET/$rel" || die "$EXIT_FAILED" "could not make $rel executable" ;;
        esac
    done <<< "$shipped"
    if [ -d "$TARGET/skills/$NAME" ]; then
        while IFS= read -r rel; do
            [ -n "$rel" ] || continue
            printf '%s\n' "$shipped" | grep -qxF "$rel" && continue
            printf '  %-7s %s  (not in this package; left in place)\n' extra "$rel"
            extras=$((extras+1))
        done <<< "$( (CDPATH= cd -- "$TARGET" && find "skills/$NAME" -type f ! -name .DS_Store | LC_ALL=C sort) )"
    fi
    say "  $copies to copy, $updates to update (each backed up first), $modes to make executable, $same unchanged, $extras not in the package"
}

reminder_command() {
    # The default folder keeps the portable ~ form; any other folder gets its absolute path.
    if [ "$TARGET" -ef "$HOME/.claude" ]; then
        printf 'bash ~/.claude/hooks/%s' "$REMINDER"
    else
        printf 'bash "%s/hooks/%s"' "$TARGET" "$REMINDER"
    fi
}

resolve_link() {
    # resolve_link <path> -> the path a chain of symlinks ends at (the path itself when it is no link)
    local p="$1" link hops=0
    while [ -L "$p" ]; do
        hops=$((hops+1))
        [ "$hops" -le "$MAX_LINK_HOPS" ] || return 1
        link="$(readlink "$p")" || return 1
        case "$link" in
            /*) p="$link" ;;
            *) p="$(CDPATH= cd -- "$(dirname "$p")" && pwd)/$link" || return 1 ;;
        esac
    done
    printf '%s\n' "$p"
}

check_settings() {
    # check_settings <settings.json> -> returns when the entry can be added to it; dies otherwise
    "$JQ" -e true "$1" >/dev/null 2>&1 \
        || die "$EXIT_FAILED" "$1 is not valid JSON; fix it first (nothing was changed)"
    "$JQ" -e -s "$JQ_SHAPE_OK" "$1" >/dev/null 2>&1 \
        || die "$EXIT_FAILED" "$1 is not one JSON object whose hooks.UserPromptSubmit is a list of hook groups; fix it first (nothing was changed)"
}

write_reminder_entry() {
    # write_reminder_entry <settings.json> <the file it resolves to> <hook command> -> adds the entry.
    # The old file is backed up before any temporary file exists. The new content goes into a
    # temporary file beside the real one: mktemp makes it private, and for an existing file cp -p
    # first gives it the original's mode, so no copy is ever more readable than the original. It
    # is checked, then swapped in whole.
    local settings="$1" real="$2" cmd="$3" tmp failed=no
    [ -f "$settings" ] && backup_file settings.json
    tmp="$(mktemp "$(dirname "$real")/.settings.json.XXXXXX")" \
        || die "$EXIT_FAILED" "cannot create a temporary file beside $real (settings.json was not changed)"
    if [ -f "$settings" ]; then
        cp -p "$settings" "$tmp" \
            && "$JQ" --arg cmd "$cmd" --arg msg "$REMINDER_STATUS_MESSAGE" "$JQ_ADD_REMINDER" "$settings" > "$tmp" \
            || failed=yes
    else
        printf '{}\n' | "$JQ" --arg cmd "$cmd" --arg msg "$REMINDER_STATUS_MESSAGE" "$JQ_ADD_REMINDER" > "$tmp" || failed=yes
    fi
    if [ "$failed" = yes ] || ! "$JQ" -e . "$tmp" >/dev/null 2>&1 \
       || [ "$("$JQ" --arg name "$REMINDER" "$JQ_COUNT_REMINDER" "$tmp")" != 1 ]; then
        rm -f "$tmp"
        die "$EXIT_FAILED" "could not add the entry to $settings (settings.json was not changed)"
    fi
    mv -f "$tmp" "$real" || { rm -f "$tmp"; die "$EXIT_FAILED" "could not write $real (settings.json was not changed)"; }
}

register_step() {
    [ "$REGISTER" = yes ] || return 0
    local settings="$TARGET/settings.json" real cmd count
    # A settings.json kept in a dotfiles repo is often a symlink: write its target and keep the link.
    real="$(resolve_link "$settings")" \
        || die "$EXIT_FAILED" "cannot resolve the symlink $settings (a loop, or more than $MAX_LINK_HOPS links); nothing was changed"
    cmd="$(reminder_command)"
    say "Reminder hook (settings.json):"
    if [ -f "$settings" ]; then
        check_settings "$settings"
        count="$("$JQ" --arg name "$REMINDER" "$JQ_COUNT_REMINDER" "$settings")" \
            || die "$EXIT_FAILED" "could not read the hooks in $settings (nothing was changed)"
        if [ "$count" -gt 0 ]; then
            say "  already registered; nothing to add"
            return 0
        fi
    fi
    say "  add a UserPromptSubmit entry: $cmd"
    [ "$APPLY" = yes ] || return 0
    write_reminder_entry "$settings" "$real" "$cmd"
    say "  registered; Claude Code picks the change up without a restart"
}

write_denylist_template() {
    cat > "$1" <<'DENYLIST'
# Private terms that must never appear in a web-research query (checked by scrub-check).
# One term per line, at least four characters; matching ignores case and finds a term
# anywhere in a line. Lines starting with # are comments.
# Add: client and employer names, project code names, private repository names, people.
# Web research stays blocked until at least one term is listed here.
DENYLIST
}

opt_in_step() {
    [ "$OPT_IN" = yes ] || return 0
    local ledger="${CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR:-$TARGET/$NAME}"
    say "Opt-in (this machine becomes the sweeper):"
    # Both are created private: the denylist will name clients and employers.
    if [ -d "$ledger" ]; then
        say "  the ledger folder exists: $ledger"
    else
        say "  create the ledger folder $ledger"
        [ "$APPLY" = yes ] && { (umask "$PRIVATE_UMASK" && mkdir -p "$ledger") || die "$EXIT_FAILED" "cannot create $ledger"; }
    fi
    if [ -f "$ledger/denylist.txt" ]; then
        say "  denylist.txt exists; left as it is"
    else
        say "  write a denylist template (no terms yet, so web research stays blocked until you add yours)"
        [ "$APPLY" = yes ] && { (umask "$PRIVATE_UMASK" && write_denylist_template "$ledger/denylist.txt") \
            || die "$EXIT_FAILED" "cannot write $ledger/denylist.txt"; }
    fi
    if ! [ "$TARGET" -ef "$HOME/.claude" ] && [ -z "${CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR:-}" ]; then
        say "  note: the hook and helper look for the ledger under ~/.claude; set CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$ledger (resources/wiring.md, Tunables)"
    fi
}

next_steps() {
    say "Next:"
    say "  - run /agents in Claude Code; if the two new agents are not listed yet, start a new session"
    [ "$OPT_IN" = yes ] && say "  - add your private terms to the denylist before the first sweep"
    say "  - check the wiring: bash \"$TARGET/hooks/$REMINDER\" --status"
    say "  - run the tests: bash \"$TARGET/hooks/tests/test-$NAME-package.sh\" (and -helper, -reminder, -install)"
}

main() {
    parse_args "$@"
    preflight
    if [ "$APPLY" = yes ]; then
        say "$NAME installer"
    else
        say "$NAME installer — DRY RUN: nothing changes until you add --yes"
    fi
    say "  package: $SOURCE_ROOT"
    say "  target:  $TARGET"
    copy_step
    register_step
    opt_in_step
    if [ "$APPLY" = yes ]; then
        [ -z "$BACKUP_DIR" ] || say "Backups of replaced files: $BACKUP_DIR"
        next_steps
    fi
    return 0
}

main "$@"
