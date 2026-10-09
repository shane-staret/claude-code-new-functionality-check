#!/bin/bash
# test-claude-code-new-functionality-check-install.sh — offline tests for the package installer.
#
# Hermetic: the installer is found relative to this suite (hooks/tests/ sits two
# levels below the folder that holds skills/, agents/ and hooks/), and every run
# gets a throwaway HOME, so the same file runs in place under ~/.claude and from a
# fresh clone of the public repository. It never touches the user's own config.
#
# Verifies: --help names every option; the dry run changes nothing; --yes copies the
# whole package; a changed file is backed up OUTSIDE skills/ and agents/ before it is
# replaced, in a backup folder no other run shares; identical files are skipped, and
# a script that lost its executable bit is repaired; files the package does not ship
# are reported, never deleted; run from inside its own target it copies nothing; an
# unwritable target or a failure part-way exits 2 and says where the backups are;
# CDPATH never redirects a path, and a target path with a newline is refused;
# --register-reminder adds exactly one entry, keeps everything else and the file's
# mode, backs the file up, follows absolute, relative and chained symlinks, refuses
# a link loop, invalid JSON, a wrongly shaped settings.json and an unquotable target
# path, never leaves a temporary file or a copy more readable than the original, and
# needs jq; --opt-in creates a private ledger folder and denylist template that keeps
# research blocked; an existing denylist is never overwritten; the README's quick start
# leaves a complete, self-consistent install. bash-3.2-safe.

set -u
unset CDPATH    # an exported CDPATH would redirect this suite's own cd calls
ROOT="${NEW_FUNCTIONALITY_CHECK_PACKAGE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
NAME="claude-code-new-functionality-check"
INSTALLER="$ROOT/skills/$NAME/install.sh"
REMINDER="$NAME-reminder.sh"
BACKUPS_REL=".claude/backups/$NAME-install"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/$NAME-install-test.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT
# Spell the sandbox as pwd does (a TMPDIR ending in / gives mktemp a //), as the installer
# spells every path it prints. Work from inside it, so a path resolved against the current
# folder by mistake lands in the sandbox, never in the folder the suite was started from.
SANDBOX="$(cd "$SANDBOX" && pwd)"
cd "$SANDBOX" || exit 1

PASS=0
FAIL=0
SKIP=0
check() {
    # check <name> <expected> <actual>
    if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS: $1"; else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected [$2], got [$3])"; fi
}
skip() { SKIP=$((SKIP+1)); echo "SKIP-LOUD: $1"; }   # run-all-tests.sh labels a suite that prints SKIP-LOUD
yes_no() { if "$@"; then echo yes; else echo no; fi; }
contains() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }

PACKAGE_FILES="$( (cd "$ROOT" && find "skills/$NAME" -type f ! -name .DS_Store | LC_ALL=C sort)
printf '%s\n' "agents/$NAME-evaluator.md" "agents/$NAME-researcher.md" "hooks/$REMINDER" \
    "hooks/tests/test-$NAME-helper.sh" "hooks/tests/test-$NAME-reminder.sh" \
    "hooks/tests/test-$NAME-install.sh" "hooks/tests/test-$NAME-package.sh")"
PACKAGE_COUNT="$(printf '%s\n' "$PACKAGE_FILES" | grep -c .)"

HOME_N=0
H=""
new_home() {
    # new_home -> sets H to a new HOME holding an empty .claude (a machine where Claude Code
    # has run). It sets a global rather than printing, because a $(...) call would bump the
    # counter in a subshell and hand every case the same HOME.
    HOME_N=$((HOME_N+1))
    H="$SANDBOX/home$HOME_N"
    mkdir -p "$H/.claude"
}
install_as() {
    # install_as <home> [installer args...] — the copy of the installer in this package
    local h="$1"; shift
    env -u CLAUDE_CONFIG_DIR -u CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR -u NEW_FUNCTIONALITY_CHECK_JQ \
        HOME="$h" bash "$INSTALLER" "$@"
}
tree_of() { (cd "$1" && find . | LC_ALL=C sort); }
all_identical() {
    # all_identical <target root> -> "yes", or the first path that is missing or differs
    local rel
    while IFS= read -r rel; do
        cmp -s "$ROOT/$rel" "$1/$rel" || { echo "$rel"; return; }
    done <<< "$PACKAGE_FILES"
    echo yes
}
backup_runs() { ls -1 "$1/$BACKUPS_REL" 2>/dev/null | grep -c .; }
valid_json() { jq -e . "$1" >/dev/null 2>&1; }
reminder_entries() { jq '[.hooks.UserPromptSubmit[]?.hooks[]? | tostring | select(contains("'"$REMINDER"'"))] | length' "$1" 2>/dev/null; }
perm_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1" 2>/dev/null; }   # GNU first: BSD stat has no -c
run_bounded() {
    # run_bounded <seconds> <command...> -> the command's exit status, or 124 when it was still
    # running after <seconds>. The command gets its own process group (set -m), and the whole
    # group is killed: a loop inside a $(...) subshell of the command would otherwise survive
    # as an orphan and hold this function's output pipe open forever.
    local limit=$(( $1 * 10 )) ticks=0 pid
    shift
    set -m
    "$@" & pid=$!
    set +m
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$ticks" -ge "$limit" ]; then
            kill -TERM -- "-$pid" 2>/dev/null; wait "$pid" 2>/dev/null
            return 124
        fi
        sleep 0.1; ticks=$((ticks+1))
    done
    wait "$pid"
}
LOOP_DEADLINE_SECS=20               # a link loop must be refused well before this
PINNED_STAMP="20260101T000000Z"     # what the fixed clock below reports

HAVE_JQ=no
command -v jq >/dev/null 2>&1 && HAVE_JQ=yes

# 0. The installer ships and parses.
check "install.sh exists" yes "$(yes_no test -s "$INSTALLER")"
check "install.sh parses (bash -n)" yes "$(yes_no bash -n "$INSTALLER")"

# 1. Usage.
new_home
HELP="$(install_as "$H" --help 2>&1)"; RC=$?
check "--help exits 0" 0 "$RC"
check "--help prints the usage" yes "$(contains "$HELP" "Usage:")"
# Every option parse_args matches must be described in --help, on a line that starts with it
# ("  --yes ...", "  -h, --help ..."): an option the help leaves out is one nobody finds.
PARSED_OPTIONS="$(awk '/^parse_args\(\) \{/ { on = 1; next } on && /^}/ { exit } on' "$INSTALLER" \
    | grep -oE '^[[:space:]]+-[-a-z|]+\)' | tr -d ' )' | tr '|' '\n')"
check "the parser's options were found (--help among them)" yes \
    "$(printf '%s\n' "$PARSED_OPTIONS" | grep -qx -- '--help' && echo yes || echo no)"
UNDOCUMENTED=""
for OPT in $PARSED_OPTIONS; do
    printf '%s\n' "$HELP" | grep -qE -- "^[[:space:]]+(-[-a-z]+, )*$OPT([ ,]|\$)" || UNDOCUMENTED="$UNDOCUMENTED $OPT"
done
check "--help describes every option the parser accepts" "" "$UNDOCUMENTED"
# Warnings go to stderr, so stdout stays the plan: run with a PATH that has no curl and no python3.
TOOLS_ONLY="$SANDBOX/tools-only"; mkdir -p "$TOOLS_ONLY"
for TOOL in bash env dirname find sort cmp grep sed awk mkdir cp chmod mv rm cat date mktemp readlink ls; do
    TOOL_PATH="$(command -v "$TOOL" 2>/dev/null)" && ln -s "$TOOL_PATH" "$TOOLS_ONLY/$TOOL"
done
new_home
OUT="$(PATH="$TOOLS_ONLY" install_as "$H" 2>"$SANDBOX/stderr.txt")"; RC=$?
check "without curl and python3 the dry run still exits 0" 0 "$RC"
check "the missing-tool warnings stay off stdout" 0 "$(printf '%s\n' "$OUT" | grep -c 'was not found')"
check "both missing-tool warnings go to stderr" 2 "$(grep -c 'was not found' "$SANDBOX/stderr.txt")"
OUT="$(install_as "$H" --frobnicate 2>&1)"; RC=$?
check "an unknown option exits 1" 1 "$RC"
check "an unknown option is named" yes "$(contains "$OUT" "--frobnicate")"
OUT="$(install_as "$H" --target 2>&1)"; RC=$?
check "--target without a folder exits 1" 1 "$RC"

# 2. No config folder: refuse rather than invent one.
NOCFG="$SANDBOX/no-config-home"; mkdir -p "$NOCFG"
OUT="$(install_as "$NOCFG" --yes 2>&1)"; RC=$?
check "a missing config folder exits 1" 1 "$RC"
check "a missing config folder is not created" no "$(yes_no test -e "$NOCFG/.claude")"

# 2b. Paths are entered literally: an exported CDPATH never redirects a relative --target or the
#     installer's view of its own package, and a target path holding a newline is refused.
CDP="$SANDBOX/cdpath"; mkdir -p "$CDP/work/rel-target" "$CDP/decoy/rel-target"
BEFORE="$(tree_of "$CDP/decoy")"
new_home
OUT="$( (cd "$CDP/work" && CDPATH="$CDP/decoy" install_as "$H" --yes --target rel-target) 2>&1)"; RC=$?
check "a relative --target under an exported CDPATH exits 0" 0 "$RC"
check "a relative --target is the folder in the current directory, not one CDPATH names" yes "$(all_identical "$CDP/work/rel-target")"
check "nothing is written under the folder CDPATH names" "$BEFORE" "$(tree_of "$CDP/decoy")"
new_home
OUT="$( (cd "$ROOT/skills" && env -u CLAUDE_CONFIG_DIR -u CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR CDPATH=. HOME="$H" \
    bash "$NAME/install.sh" --target "$H/.claude") 2>&1)"; RC=$?
check "run by a relative path under CDPATH=., the installer exits 0" 0 "$RC"
check "and names its own package folder once" "  package: $(cd "$ROOT" && pwd)" "$(printf '%s\n' "$OUT" | grep '^  package:')"
NL='
'
NLDIR="$SANDBOX/new${NL}line"; mkdir -p "$NLDIR"
new_home
OUT="$(install_as "$H" --yes --target "$NLDIR" 2>&1)"; RC=$?
check "a target path holding a newline exits 1" 1 "$RC"
check "a target path holding a newline is refused by name" yes "$(contains "$OUT" "newline")"
check "nothing is installed into a folder whose path holds a newline" "" "$(ls -A "$NLDIR")"

# 3. The dry run lists every file and changes nothing. (Without jq, --register-reminder is
#    refused by design, which section 9 covers; the dry run then plans the rest.)
new_home
BEFORE="$(tree_of "$H")"
if [ "$HAVE_JQ" = yes ]; then DRY_FLAGS="--register-reminder --opt-in"; else DRY_FLAGS="--opt-in"; fi
# shellcheck disable=SC2086
OUT="$(install_as "$H" $DRY_FLAGS 2>&1)"; RC=$?
check "the dry run exits 0" 0 "$RC"
check "the dry run says it is one" yes "$(contains "$OUT" "DRY RUN")"
check "the dry run lists every package file as a copy" "$PACKAGE_COUNT" "$(printf '%s\n' "$OUT" | grep -c '^  copy ')"
check "the dry run changes nothing (files, settings, ledger)" "$BEFORE" "$(tree_of "$H")"

# 4. --yes copies the whole package; scripts stay executable; nothing is backed up.
OUT="$(install_as "$H" --yes 2>&1)"; RC=$?
check "--yes exits 0" 0 "$RC"
check "--yes installs every package file byte for byte" yes "$(all_identical "$H/.claude")"
check "the helper is executable after install" yes "$(yes_no test -x "$H/.claude/skills/$NAME/claude_code_new_functionality_check.sh")"
check "the hook is executable after install" yes "$(yes_no test -x "$H/.claude/hooks/$REMINDER")"
check "the installer is executable after install" yes "$(yes_no test -x "$H/.claude/skills/$NAME/install.sh")"
check "a first install backs nothing up" 0 "$(backup_runs "$H")"
check "--yes alone writes no settings.json" no "$(yes_no test -e "$H/.claude/settings.json")"
check "--yes alone does not opt the machine in" no "$(yes_no test -e "$H/.claude/$NAME")"

# 5. A second run finds everything in place.
OUT="$(install_as "$H" --yes 2>&1)"; RC=$?
check "a second --yes exits 0" 0 "$RC"
check "a second --yes copies nothing" 0 "$(printf '%s\n' "$OUT" | grep -c -E '^  (copy|update) ')"
check "a second --yes reports every file unchanged" "$PACKAGE_COUNT" "$(printf '%s\n' "$OUT" | grep -c '^  same ')"
check "a second --yes backs nothing up" 0 "$(backup_runs "$H")"

# 5b. A script whose content is unchanged but which lost its executable bit is repaired and
#     reported as a mode fix; the dry run only reports it.
chmod -x "$H/.claude/hooks/$REMINDER"
OUT="$(install_as "$H" 2>&1)"; RC=$?
check "the dry run reports a lost executable bit as a mode fix" 1 "$(printf '%s\n' "$OUT" | grep -c "^  mode    hooks/$REMINDER")"
check "the dry run leaves the bit alone" no "$(yes_no test -x "$H/.claude/hooks/$REMINDER")"
OUT="$(install_as "$H" --yes 2>&1)"; RC=$?
check "a run that repairs an executable bit exits 0" 0 "$RC"
check "the repair is reported as a mode fix" 1 "$(printf '%s\n' "$OUT" | grep -c "^  mode    hooks/$REMINDER")"
check "the script is executable again" yes "$(yes_no test -x "$H/.claude/hooks/$REMINDER")"
check "a mode fix backs nothing up" 0 "$(backup_runs "$H")"

# 6. A changed file is backed up outside skills/ and agents/; an extra file is left alone.
printf 'a local edit\n' >> "$H/.claude/skills/$NAME/SKILL.md"
cp "$H/.claude/skills/$NAME/SKILL.md" "$SANDBOX/edited-SKILL.md"
printf 'my own notes\n' > "$H/.claude/skills/$NAME/resources/my-notes.md"
OUT="$(install_as "$H" --yes 2>&1)"; RC=$?
check "an update run exits 0" 0 "$RC"
check "the changed file is reported as an update" 1 "$(printf '%s\n' "$OUT" | grep -c "^  update  skills/$NAME/SKILL.md")"
check "the changed file is restored to the package version" yes "$(yes_no cmp -s "$ROOT/skills/$NAME/SKILL.md" "$H/.claude/skills/$NAME/SKILL.md")"
check "exactly one backup folder was made" 1 "$(backup_runs "$H")"
BK="$(ls -1d "$H/$BACKUPS_REL"/*/ 2>/dev/null | head -1)"
check "the backup holds the edited file at its own path" yes "$(yes_no cmp -s "$SANDBOX/edited-SKILL.md" "${BK}skills/$NAME/SKILL.md")"
check "no backup copy lands inside skills/ or agents/" "" "$(find "$H/.claude/skills" "$H/.claude/agents" -name '*.bak*' 2>/dev/null)"
check "a file the package does not ship is reported" 1 "$(printf '%s\n' "$OUT" | grep -c "^  extra   skills/$NAME/resources/my-notes.md")"
check "a file the package does not ship is never deleted" yes "$(yes_no test -f "$H/.claude/skills/$NAME/resources/my-notes.md")"

# 7. Run from inside its own target, the installer copies nothing.
BEFORE="$(tree_of "$H")"
OUT="$(env -u CLAUDE_CONFIG_DIR -u CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR HOME="$H" bash "$H/.claude/skills/$NAME/install.sh" --yes 2>&1)"; RC=$?
check "in place: exits 0" 0 "$RC"
check "in place: says it is already installed there" yes "$(contains "$OUT" "already installed here")"
check "in place: nothing changes" "$BEFORE" "$(tree_of "$H")"

# 7b. Two update runs in the same second never share a backup folder, so the first run's copy is
#     never overwritten. A fixed clock first on PATH makes both runs see the same second.
FIXED_CLOCK="$SANDBOX/fixed-clock"; mkdir -p "$FIXED_CLOCK"
printf '#!/bin/sh\necho %s\n' "$PINNED_STAMP" > "$FIXED_CLOCK/date"; chmod +x "$FIXED_CLOCK/date"
new_home
install_as "$H" --yes >/dev/null 2>&1
printf 'first local edit\n' >> "$H/.claude/skills/$NAME/SKILL.md"
cp "$H/.claude/skills/$NAME/SKILL.md" "$SANDBOX/first-edit.md"
PATH="$FIXED_CLOCK:$PATH" install_as "$H" --yes >/dev/null 2>&1
printf 'second local edit\n' >> "$H/.claude/skills/$NAME/SKILL.md"
cp "$H/.claude/skills/$NAME/SKILL.md" "$SANDBOX/second-edit.md"
PATH="$FIXED_CLOCK:$PATH" install_as "$H" --yes >/dev/null 2>&1
check "two update runs in the same second make two backup folders" 2 "$(backup_runs "$H")"
check "both backup folders are named for that second" 2 "$(ls -1 "$H/$BACKUPS_REL" 2>/dev/null | grep -c "^$PINNED_STAMP")"
KEPT=0
for BK in "$H/$BACKUPS_REL"/*/; do
    cmp -s "$SANDBOX/first-edit.md" "${BK}skills/$NAME/SKILL.md" && KEPT=$((KEPT+1))
    cmp -s "$SANDBOX/second-edit.md" "${BK}skills/$NAME/SKILL.md" && KEPT=$((KEPT+1))
done
check "each run's backup keeps its own copy (the first is never overwritten)" 2 "$KEPT"

# 7c. A target that cannot be written: the copy step fails loudly (exit 2) and says what it could
#     not do. (root ignores file modes, so this case and 7d cannot run as root.)
if [ "$(id -u)" -ne 0 ]; then
    new_home
    chmod 555 "$H/.claude"
    OUT="$(install_as "$H" --yes 2>&1)"; RC=$?
    chmod 755 "$H/.claude"
    check "an unwritable target exits 2" 2 "$RC"
    check "an unwritable target is named in the message" yes "$(contains "$OUT" "could not copy")"

    # 7d. A copy that fails part-way says where the backups it already took are.
    new_home
    install_as "$H" --yes >/dev/null 2>&1
    printf 'a local edit\n' >> "$H/.claude/skills/$NAME/SKILL.md"
    chmod 444 "$H/.claude/skills/$NAME/SKILL.md"    # it is backed up, then cannot be replaced
    OUT="$(install_as "$H" --yes 2>&1)"; RC=$?
    chmod 644 "$H/.claude/skills/$NAME/SKILL.md"
    BK="$(ls -1d "$H/$BACKUPS_REL"/*/ 2>/dev/null | head -1)"
    [ -n "$BK" ] || BK="NO-BACKUP-FOLDER-WAS-MADE/"   # an empty needle would match any output
    check "a copy that fails part-way exits 2" 2 "$RC"
    check "the failure names the backup folder already in use" yes "$(contains "$OUT" "${BK%/}")"
else
    skip "running as root, which ignores file modes: the unwritable-target and part-way cases did not run"
fi

# 8. --register-reminder.
if [ "$HAVE_JQ" = yes ]; then
    new_home
    OUT="$(umask 022; install_as "$H" --yes --register-reminder 2>&1)"; RC=$?
    check "register without a settings.json exits 0" 0 "$RC"
    check "register creates a valid settings.json" yes "$(yes_no valid_json "$H/.claude/settings.json")"
    check "a new settings.json is private (mode 600, whatever the umask)" 600 "$(perm_of "$H/.claude/settings.json")"
    check "register adds exactly one reminder entry" 1 "$(reminder_entries "$H/.claude/settings.json")"
    check "the entry uses the portable ~/.claude path for the default folder" \
        "bash ~/.claude/hooks/$REMINDER" \
        "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$H/.claude/settings.json" 2>/dev/null)"
    check "the entry is a command hook with a status message" "command|true" \
        "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0] | "\(.type)|\(has("statusMessage"))"' "$H/.claude/settings.json" 2>/dev/null)"
    OUT="$(install_as "$H" --yes --register-reminder 2>&1)"; RC=$?
    check "registering twice exits 0" 0 "$RC"
    check "registering twice keeps one entry" 1 "$(reminder_entries "$H/.claude/settings.json")"
    check "registering twice says it is already registered" yes "$(contains "$OUT" "already registered")"
    check "registering twice backs nothing up" 0 "$(backup_runs "$H")"

    # An existing settings.json: the entry joins the no-matcher group; nothing else moves.
    new_home
    cat > "$H/.claude/settings.json" <<'JSON'
{
  "model": "keep-me",
  "permissions": {"deny": ["Read(**/.env)"]},
  "hooks": {
    "UserPromptSubmit": [
      {"matcher": "only-this", "hooks": [{"type": "command", "command": "echo matcher-group"}]},
      {"hooks": [{"type": "command", "command": "echo every-prompt"}]}
    ],
    "Stop": [{"hooks": [{"type": "command", "command": "echo stop"}]}]
  }
}
JSON
    cp "$H/.claude/settings.json" "$SANDBOX/original-settings.json"
    OUT="$(install_as "$H" --yes --register-reminder 2>&1)"; RC=$?
    check "register into an existing settings.json exits 0" 0 "$RC"
    check "register adds exactly one entry to an existing file" 1 "$(reminder_entries "$H/.claude/settings.json")"
    check "the entry joins the group without a matcher" "echo every-prompt|bash ~/.claude/hooks/$REMINDER" \
        "$(jq -r '.hooks.UserPromptSubmit[1].hooks | map(.command) | join("|")' "$H/.claude/settings.json" 2>/dev/null)"
    check "everything else in settings.json is unchanged" \
        "$(jq -S '.hooks.UserPromptSubmit[1].hooks |= .[0:1]' "$SANDBOX/original-settings.json")" \
        "$(jq -S '.hooks.UserPromptSubmit[1].hooks |= .[0:1]' "$H/.claude/settings.json" 2>/dev/null)"
    BK="$(ls -1d "$H/$BACKUPS_REL"/*/ 2>/dev/null | head -1)"
    check "the old settings.json is backed up first" yes "$(yes_no cmp -s "$SANDBOX/original-settings.json" "${BK}settings.json")"

    # Only matcher groups: a new every-prompt group is added.
    new_home
    printf '%s\n' '{"hooks": {"UserPromptSubmit": [{"matcher": "x", "hooks": [{"type": "command", "command": "echo x"}]}]}}' > "$H/.claude/settings.json"
    install_as "$H" --yes --register-reminder >/dev/null 2>&1
    check "with only matcher groups, a new group without a matcher is added" "2|null" \
        "$(jq -r '.hooks.UserPromptSubmit | "\(length)|\(.[1].matcher)"' "$H/.claude/settings.json" 2>/dev/null)"

    # Invalid JSON: refuse, change nothing.
    new_home
    printf '{ not json\n' > "$H/.claude/settings.json"
    OUT="$(install_as "$H" --yes --register-reminder 2>&1)"; RC=$?
    check "an invalid settings.json exits 2" 2 "$RC"
    check "an invalid settings.json is left as it was" "{ not json" "$(cat "$H/.claude/settings.json")"
    check "an invalid settings.json is named in the message" yes "$(contains "$OUT" "not valid JSON")"

    # A settings.json that is a symlink (a dotfiles repo, say) stays a symlink; the entry lands in its target.
    new_home
    mkdir -p "$SANDBOX/dotfiles"
    printf '%s\n' '{"model": "keep-me"}' > "$SANDBOX/dotfiles/claude-settings.json"
    ln -s "$SANDBOX/dotfiles/claude-settings.json" "$H/.claude/settings.json"
    OUT="$(install_as "$H" --yes --register-reminder 2>&1)"; RC=$?
    check "register through a symlinked settings.json exits 0" 0 "$RC"
    check "the symlink is kept, not replaced by a plain file" yes "$(yes_no test -L "$H/.claude/settings.json")"
    check "the entry lands in the symlink's target" 1 "$(reminder_entries "$SANDBOX/dotfiles/claude-settings.json")"
    check "the target keeps its other settings" "keep-me" "$(jq -r .model "$SANDBOX/dotfiles/claude-settings.json" 2>/dev/null)"
    check "no temporary file is left beside the link or its target" "" \
        "$(ls -A "$H/.claude" "$SANDBOX/dotfiles" 2>/dev/null | grep -F '.settings.json.' || true)"

    # A relative link resolves against the link's own folder, never the current one: the run starts
    # in / so a wrong resolution cannot find the file by accident.
    new_home
    mkdir -p "$H/linked-config"
    printf '%s\n' '{"model": "keep-me"}' > "$H/linked-config/settings.json"
    ln -s ../linked-config/settings.json "$H/.claude/settings.json"
    OUT="$( (cd / && install_as "$H" --yes --register-reminder) 2>&1)"; RC=$?
    check "register through a relative symlink exits 0" 0 "$RC"
    check "the relative symlink is kept as it was" "../linked-config/settings.json" "$(readlink "$H/.claude/settings.json")"
    check "the entry lands in the relative symlink's target" 1 "$(reminder_entries "$H/linked-config/settings.json")"

    # A chain of links (relative, relative, then absolute) is followed to its end; every link stays.
    new_home
    mkdir -p "$H/chain" "$H/chain-end"
    printf '%s\n' '{"model": "keep-me"}' > "$H/chain-end/settings.json"
    ln -s "$H/chain-end/settings.json" "$H/chain/second.json"
    ln -s second.json "$H/chain/first.json"
    ln -s ../chain/first.json "$H/.claude/settings.json"
    OUT="$( (cd / && install_as "$H" --yes --register-reminder) 2>&1)"; RC=$?
    check "register through a chain of three links exits 0" 0 "$RC"
    check "every link in the chain is kept" "../chain/first.json|second.json|$H/chain-end/settings.json" \
        "$(readlink "$H/.claude/settings.json")|$(readlink "$H/chain/first.json")|$(readlink "$H/chain/second.json")"
    check "the entry lands at the end of the chain" 1 "$(reminder_entries "$H/chain-end/settings.json")"
    check "the end of the chain keeps its other settings" "keep-me" "$(jq -r .model "$H/chain-end/settings.json" 2>/dev/null)"

    # A link loop is refused promptly, because the resolver gives up after a fixed number of hops,
    # and nothing changes. (Exit 124 here would mean the resolver never stopped.)
    new_home
    install_as "$H" --yes >/dev/null 2>&1
    ln -s loop-b.json "$H/.claude/settings.json"
    ln -s settings.json "$H/.claude/loop-b.json"
    BEFORE="$(tree_of "$H")"
    OUT="$(run_bounded "$LOOP_DEADLINE_SECS" env -u CLAUDE_CONFIG_DIR -u CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR \
        -u NEW_FUNCTIONALITY_CHECK_JQ HOME="$H" bash "$INSTALLER" --yes --register-reminder 2>&1)"; RC=$?
    check "a settings.json link loop exits 2" 2 "$RC"
    check "a link loop is named in the message" yes "$(contains "$OUT" "cannot resolve the symlink")"
    check "a link loop changes nothing" "$BEFORE" "$(tree_of "$H")"
    check "the looping links are left as they were" "loop-b.json|settings.json" \
        "$(readlink "$H/.claude/settings.json")|$(readlink "$H/.claude/loop-b.json")"

    # The file keeps its permissions: the new content is written through a copy that kept them.
    new_home
    printf '%s\n' '{"model": "keep-me"}' > "$H/.claude/settings.json"
    chmod 640 "$H/.claude/settings.json"
    install_as "$H" --yes --register-reminder >/dev/null 2>&1
    check "a 0640 settings.json keeps mode 640 after the entry is added" 640 "$(perm_of "$H/.claude/settings.json")"
    check "and gains the entry" 1 "$(reminder_entries "$H/.claude/settings.json")"

    # While the entry is written, no temporary copy of a private settings.json is readable by
    # anyone else, even under umask 022. A jq wrapper lists the folder each time it runs.
    new_home
    printf '%s\n' '{"env": {"EXAMPLE_SETTING": "a private value"}}' > "$H/.claude/settings.json"
    chmod 600 "$H/.claude/settings.json"
    SPY="$SANDBOX/jq-spy"
    printf '#!/bin/sh\nls -la "$SPY_DIR" >> "$SPY_LOG"\nexec "$REAL_JQ" "$@"\n' > "$SPY"; chmod +x "$SPY"
    (umask 022; env -u CLAUDE_CONFIG_DIR -u CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR HOME="$H" \
        NEW_FUNCTIONALITY_CHECK_JQ="$SPY" SPY_DIR="$H/.claude" SPY_LOG="$SANDBOX/jq-spy.log" REAL_JQ="$(command -v jq)" \
        bash "$INSTALLER" --yes --register-reminder >/dev/null 2>&1)
    check "the entry was added with the jq wrapper in place" 1 "$(reminder_entries "$H/.claude/settings.json")"
    check "every temporary copy of a 0600 settings.json is 0600 too" "-rw-------" \
        "$(grep -F '.settings.json.' "$SANDBOX/jq-spy.log" 2>/dev/null | cut -c1-10 | sort -u | tr '\n' ' ' | sed 's/ $//')"
    check "the private settings.json stays private" 600 "$(perm_of "$H/.claude/settings.json")"

    # A backup that cannot be made stops the run before any temporary file exists.
    new_home
    printf '%s\n' '{"model": "keep-me"}' > "$H/.claude/settings.json"
    : > "$H/.claude/backups"    # a plain file where the backups folder would go
    OUT="$(install_as "$H" --yes --register-reminder 2>&1)"; RC=$?
    check "a settings.json that cannot be backed up exits 2" 2 "$RC"
    check "a settings.json that cannot be backed up is left as it was" '{"model": "keep-me"}' "$(cat "$H/.claude/settings.json")"
    check "a failed backup leaves no temporary file behind" "" "$(ls -A "$H/.claude" | grep -F '.settings.json.' || true)"

    # An empty settings.json, or valid JSON of the wrong shape, is refused before anything is
    # written or backed up. (The package is installed first, so the refused run copies nothing.)
    for SHAPE in '' '[]' '{"hooks": []}' '{"hooks": {"UserPromptSubmit": "every prompt"}}' \
                 '{"hooks": {"UserPromptSubmit": [{"hooks": "not a list"}]}}'; do
        new_home
        install_as "$H" --yes >/dev/null 2>&1
        printf '%s' "$SHAPE" > "$H/.claude/settings.json"
        BEFORE="$(tree_of "$H")"
        OUT="$(install_as "$H" --yes --register-reminder 2>&1)"; RC=$?
        check "a settings.json holding [$SHAPE] exits 2" 2 "$RC"
        check "a settings.json holding [$SHAPE] is left as it was" "$SHAPE" "$(cat "$H/.claude/settings.json")"
        check "a settings.json holding [$SHAPE] gets no backup and no temporary file" "$BEFORE" "$(tree_of "$H")"
    done

    # A custom config folder with a space: the hook path is absolute and quoted, and it runs.
    CUSTOM="$SANDBOX/custom config/.claude"; mkdir -p "$CUSTOM"
    CUSTOM="$(cd "$CUSTOM" && pwd)"   # the installer names the folder as pwd spells it
    new_home
    OUT="$(install_as "$H" --yes --register-reminder --target "$CUSTOM" 2>&1)"; RC=$?
    check "--target exits 0" 0 "$RC"
    check "--target installs there" yes "$(all_identical "$CUSTOM")"
    CMD="$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$CUSTOM/settings.json" 2>/dev/null)"
    check "--target registers the absolute, quoted hook path" "bash \"$CUSTOM/hooks/$REMINDER\"" "$CMD"
    OUT="$(env HOME="$H" bash -c "$CMD --status" 2>&1)"; RC=$?
    check "the registered command runs as written" 0 "$RC"
else
    skip "jq is not installed: the --register-reminder cases did not run"
fi

# 8b. The target path goes into a hook command that runs on every prompt, so --register-reminder
#     refuses a path holding a character that cannot be quoted safely there. The same folder still
#     takes the package itself. (No jq needed: the path is checked first.)
for ODD in 'with"quote' 'with$dollar' 'with`backtick' 'with\backslash'; do
    ODD_DIR="$SANDBOX/odd-targets/$ODD"; mkdir -p "$ODD_DIR"
    new_home
    BEFORE="$(tree_of "$ODD_DIR")"
    OUT="$(install_as "$H" --yes --register-reminder --target "$ODD_DIR" 2>&1)"; RC=$?
    check "register into a folder named '$ODD' exits 1" 1 "$RC"
    check "register into '$ODD' says the path cannot be quoted safely" yes "$(contains "$OUT" "cannot be quoted safely")"
    check "register into '$ODD' writes no settings.json" no "$(yes_no test -e "$ODD_DIR/settings.json")"
    check "register into '$ODD' leaves the folder as it was" "$BEFORE" "$(tree_of "$ODD_DIR")"
    OUT="$(install_as "$H" --yes --target "$ODD_DIR" 2>&1)"; RC=$?
    check "without --register-reminder, '$ODD' takes the package (exit 0)" 0 "$RC"
    check "without --register-reminder, '$ODD' gets every package file" yes "$(all_identical "$ODD_DIR")"
done

# 9. --register-reminder needs jq, and says what to do instead; nothing is changed.
new_home
BEFORE="$(tree_of "$H")"
OUT="$(env -u CLAUDE_CONFIG_DIR -u CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR HOME="$H" \
    NEW_FUNCTIONALITY_CHECK_JQ="$SANDBOX/no-such-jq" bash "$INSTALLER" --yes --register-reminder 2>&1)"; RC=$?
check "register without jq exits 1" 1 "$RC"
check "register without jq points at the manual steps" yes "$(contains "$OUT" "wiring.md")"
check "register without jq changes nothing" "$BEFORE" "$(tree_of "$H")"

# 10. CLAUDE_CONFIG_DIR is the default target.
CFG="$SANDBOX/config-dir"; mkdir -p "$CFG"
new_home
env -u CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR HOME="$H" CLAUDE_CONFIG_DIR="$CFG" bash "$INSTALLER" --yes >/dev/null 2>&1
check "CLAUDE_CONFIG_DIR is the default target" yes "$(all_identical "$CFG")"

# 11. --opt-in: the ledger folder and a denylist that keeps research blocked.
new_home
OUT="$(umask 022; install_as "$H" --yes --opt-in 2>&1)"; RC=$?
check "--opt-in exits 0" 0 "$RC"
check "--opt-in creates the ledger folder" yes "$(yes_no test -d "$H/.claude/$NAME")"
check "the ledger folder is private (mode 700, whatever the umask)" 700 "$(perm_of "$H/.claude/$NAME")"
check "--opt-in writes a denylist template" yes "$(yes_no test -s "$H/.claude/$NAME/denylist.txt")"
check "the denylist is private (mode 600: it will list private names)" 600 "$(perm_of "$H/.claude/$NAME/denylist.txt")"
if [ -f "$H/.claude/$NAME/denylist.txt" ]; then
    TERMS="$(grep -v '^[[:space:]]*#' "$H/.claude/$NAME/denylist.txt" | grep -c '[^[:space:]]')"
else
    TERMS="no file"
fi
check "the template lists no term" 0 "$TERMS"
printf 'Which hook events exist in Claude Code?\n' > "$SANDBOX/agenda.txt"
OUT="$(env -u CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR HOME="$H" bash "$H/.claude/skills/$NAME/claude_code_new_functionality_check.sh" scrub-check "$SANDBOX/agenda.txt" 2>&1)"; RC=$?
check "with the template, research stays blocked" 1 "$RC"
check "the block says the denylist lists no terms" yes "$(contains "$OUT" "lists no terms")"
OUT="$(env -u CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR -u NEW_FUNCTIONALITY_CHECK_STATE_FILE HOME="$H" bash "$H/.claude/hooks/$REMINDER" --status 2>&1)"
check "after --opt-in the hook reports NEVER-RUN" yes "$(contains "$OUT" "NEVER-RUN")"
printf 'acme-secret-project\n' > "$H/.claude/$NAME/denylist.txt"
install_as "$H" --yes --opt-in >/dev/null 2>&1
check "an existing denylist is never overwritten" "acme-secret-project" "$(cat "$H/.claude/$NAME/denylist.txt")"

# 12. The README's quick start, verbatim: dry run, then everything.
new_home
install_as "$H" >/dev/null 2>&1
if [ "$HAVE_JQ" = yes ]; then FLAGS="--yes --register-reminder --opt-in"; else FLAGS="--yes --opt-in"; fi
# shellcheck disable=SC2086
OUT="$(install_as "$H" $FLAGS 2>&1)"; RC=$?
check "the quick start exits 0" 0 "$RC"
OUT="$(env -u NEW_FUNCTIONALITY_CHECK_PACKAGE_ROOT HOME="$H" bash "$H/.claude/hooks/tests/test-$NAME-package.sh" 2>&1)"; RC=$?
check "the installed copy passes its own package suite" 0 "$RC"

echo "----"
echo "claude-code-new-functionality-check-install: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
