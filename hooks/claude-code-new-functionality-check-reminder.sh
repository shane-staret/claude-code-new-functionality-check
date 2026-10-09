#!/bin/bash
# claude-code-new-functionality-check-reminder.sh — UserPromptSubmit hook (notice-only, never blocks).
#
# Claude Code ships one or two CLI versions a day, and everything under
# ~/.claude was hand-built against whatever existed that day. Nothing else
# looks upstream, so this hook makes the look routine: when the last
# /claude-code-new-functionality-check sweep on this machine is older than the
# interval it prints a NEW-FUNCTIONALITY-CHECK notice that the live session
# consumes. The notice is NON-PREEMPTIVE — it tells the session to finish the
# user's request first — and it re-fires at most once per renotice window, so a
# deferred sweep does not nag every turn. Notices that keep being ignored are
# counted, and the wording escalates, so the check can never die quietly.
#
# OPT-IN PER MACHINE: the hook is dormant unless the ledger directory exists.
# This config deploys to several machines; only the one designated sweeper
# (mkdir the directory to opt in) is ever asked to spend tokens on sweeps.
# An opted-in machine with no ledger has never swept: its first sweep is a full
# backfill (a large multi-agent run), so that notice tells the session to ASK.
# "Never swept" is decided by the LEDGER, not by the state file: ~/.claude/tmp
# can be wiped, and a wiped state beside an intact ledger is merely due.
#
# Inside a quiet directory (for example a client-work tree where end-of-turn
# duties are already heavy; none by default) a due sweep stays silent until it is
# badly overdue.
#
# Modes:
#   (no args, stdin = UserPromptSubmit JSON)  the notice hook; always exits 0
#   --status                   print DORMANT / NEVER-RUN / DUE / FRESH; no side effects
#   --write-state "<covered>"  record a completed sweep. The /claude-code-new-functionality-check skill
#                              calls this LAST, once the core sources succeeded.
# This script is the single owner of the state format, so the hook and the skill
# can never disagree. The two modes run BEFORE the opt-out: a manual sweep on a
# machine with notices switched off must still be recorded. Mode misuse is
# loud (stderr + exit 1) — only hook mode promises exit 0.
#
# Design: no network, no model call, no blocking — a notice consumed in-session.
# bash-3.2-safe.
#
# Env:
#   CLAUDE_NEW_FUNCTIONALITY_CHECK=0                 opt out of notices (modes still work)
#   CLAUDE_NEW_FUNCTIONALITY_CHECK_INTERVAL_DAYS=N   sweep cadence in days (default 7)
#   CLAUDE_NEW_FUNCTIONALITY_CHECK_RENOTICE_SECS=N   min seconds between notices (default 86400)
#   CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=path          ledger home (default ~/.claude/claude-code-new-functionality-check)
#   CLAUDE_NEW_FUNCTIONALITY_CHECK_QUIET_DIRS=a:b    colon-separated quiet trees (default: none; each
#                                          matched as a directory, however it is spelled)
#   NEW_FUNCTIONALITY_CHECK_STATE_FILE=path          state override (tests)
#   NEW_FUNCTIONALITY_CHECK_UPDATE_RESULT_FILE=path  CLI updater record override (tests)
#   NEW_FUNCTIONALITY_CHECK_NOW=epoch                clock override (tests)

DEFAULT_INTERVAL_DAYS=7
DEFAULT_RENOTICE_SECS=86400
SECS_PER_DAY=86400
QUIET_OVERDUE_FACTOR=2        # inside a quiet dir, speak only once this many intervals have passed
ESCALATE_AFTER_NOTICES=3      # from this many ignored notices on, the wording says so
COVERED_MAX_CHARS=120
STDIN_READ_TIMEOUT_SECS=1

LEDGER_DIR="${CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR:-$HOME/.claude/claude-code-new-functionality-check}"
STATE_FILE="${NEW_FUNCTIONALITY_CHECK_STATE_FILE:-$HOME/.claude/tmp/claude-code-new-functionality-check-state.json}"
UPDATE_RESULT_FILE="${NEW_FUNCTIONALITY_CHECK_UPDATE_RESULT_FILE:-$HOME/.claude/.last-update-result.json}"
QUIET_DIRS="${CLAUDE_NEW_FUNCTIONALITY_CHECK_QUIET_DIRS:-}"
INTERVAL_DAYS="${CLAUDE_NEW_FUNCTIONALITY_CHECK_INTERVAL_DAYS:-$DEFAULT_INTERVAL_DAYS}"
RENOTICE_SECS="${CLAUDE_NEW_FUNCTIONALITY_CHECK_RENOTICE_SECS:-$DEFAULT_RENOTICE_SECS}"
# A non-numeric override falls back to the default instead of breaking arithmetic.
case "$INTERVAL_DAYS" in ''|*[!0-9]*) INTERVAL_DAYS="$DEFAULT_INTERVAL_DAYS" ;; esac
case "$RENOTICE_SECS" in ''|*[!0-9]*) RENOTICE_SECS="$DEFAULT_RENOTICE_SECS" ;; esac
MODE="${1:-}"

# --- flat-JSON field readers ------------------------------------------------
# Both files read here are single-line JSON (this hook's own state, and the CLI
# updater record), so fields are pulled with parameter expansion instead of sed:
# hook mode runs on every prompt, and each spawn costs ~30-100 ms under Windows
# Git Bash. Results land in _VALUE so that no subshell is forked either.
_VALUE=""
json_number() {
    # json_number <line> <key> -> _VALUE = the value's leading digits, or empty
    _VALUE=""
    case "$1" in
        *"\"$2\": "*) _VALUE="${1#*\"$2\": }" ;;
        *"\"$2\":"*)  _VALUE="${1#*\"$2\":}" ;;
        *) return 0 ;;
    esac
    _VALUE="${_VALUE%%[!0-9]*}"
    # Leading zeros would make bash arithmetic read the number as octal ("08" is an
    # error), so they are dropped; a value that was all zeros stays a single 0.
    case "$_VALUE" in
        0*) _VALUE="${_VALUE#"${_VALUE%%[!0]*}"}"; [ -n "$_VALUE" ] || _VALUE="0" ;;
    esac
}
json_string() {
    # json_string <line> <key> -> _VALUE = the string value, or empty
    _VALUE=""
    case "$1" in
        *"\"$2\": \""*) _VALUE="${1#*\"$2\": \"}" ;;
        *"\"$2\":\""*)  _VALUE="${1#*\"$2\":\"}" ;;
        *) return 0 ;;
    esac
    _VALUE="${_VALUE%%\"*}"
}

# --- state ------------------------------------------------------------------
LAST_RUN_EPOCH=""
LAST_RUN_UTC=""
LAST_NOTICE_EPOCH=""
NOTICES_SINCE_LAST_RUN=0
COVERED=""
read_state() {
    # A corrupt or empty file simply yields empty fields: with a ledger present
    # that reads as "due", which is the safe direction to self-heal in.
    [ -f "$STATE_FILE" ] || return 0
    _line=""
    IFS= read -r _line < "$STATE_FILE" 2>/dev/null
    json_number "$_line" last_run_epoch;         LAST_RUN_EPOCH="$_VALUE"
    json_string "$_line" last_run_utc;           LAST_RUN_UTC="$_VALUE"
    json_number "$_line" last_notice_epoch;      LAST_NOTICE_EPOCH="$_VALUE"
    json_number "$_line" notices_since_last_run; NOTICES_SINCE_LAST_RUN="${_VALUE:-0}"
    json_string "$_line" covered;                COVERED="$_VALUE"
    # 0 is how "never" is stored, so the file always has the same shape.
    [ "$LAST_RUN_EPOCH" = "0" ] && LAST_RUN_EPOCH=""
    [ "$LAST_NOTICE_EPOCH" = "0" ] && LAST_NOTICE_EPOCH=""
    return 0
}

write_state_file() {
    # write_state_file <last_run_epoch> <last_run_utc> <last_notice_epoch> <notices> <covered>
    # Written to a sibling temp file and renamed, so a reader never sees half a line.
    mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null
    _tmp="$STATE_FILE.tmp.$$"
    printf '{"last_run_epoch": %s, "last_run_utc": "%s", "last_notice_epoch": %s, "notices_since_last_run": %s, "covered": "%s"}\n' \
        "${1:-0}" "$2" "${3:-0}" "${4:-0}" "$5" 2>/dev/null > "$_tmp" || { rm -f "$_tmp" 2>/dev/null; return 1; }
    mv -f "$_tmp" "$STATE_FILE" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
}

NOW=0
read_clock() {
    NOW="${NEW_FUNCTIONALITY_CHECK_NOW:-}"
    [ -n "$NOW" ] || NOW="$(date +%s 2>/dev/null || echo 0)"
    case "$NOW" in ''|*[!0-9]*) NOW=0 ;; esac
}

INSTALLED_VERSION=""
read_installed_version() {
    # Zero-network signal: the CLI's own updater record. Purely informational —
    # a missing or reshaped file just leaves the version out of the notice.
    [ -f "$UPDATE_RESULT_FILE" ] || return 0
    _line=""
    IFS= read -r _line < "$UPDATE_RESULT_FILE" 2>/dev/null
    json_string "$_line" version_to
    INSTALLED_VERSION="$_VALUE"
}

CONDITION=""        # DORMANT | NEVER | DUE | FRESH
AGE_SECS=""         # empty when the age is unknown
AGE_TEXT=""
NEXT_DUE_DAYS=""
compute_condition() {
    if [ ! -d "$LEDGER_DIR" ]; then
        CONDITION="DORMANT"
        return 0
    fi
    if [ ! -f "$LEDGER_DIR/ledger.md" ] && [ -z "$LAST_RUN_EPOCH" ]; then
        CONDITION="NEVER"
        return 0
    fi
    CONDITION="DUE"
    if [ -z "$LAST_RUN_EPOCH" ]; then
        AGE_TEXT="at an unknown time (the state file is missing or unreadable, but the ledger is intact)"
        return 0
    fi
    _age=$(( NOW - LAST_RUN_EPOCH ))
    if [ "$_age" -lt 0 ]; then
        # A clock jump or a bogus stamp. Reading it as "fresh" would silence the
        # watch until that future date, so it reads as due instead.
        AGE_TEXT="at an unknown time (its recorded timestamp is in the future)"
        return 0
    fi
    AGE_SECS="$_age"
    AGE_TEXT="$(( _age / SECS_PER_DAY )) day(s) ago"
    _interval_secs=$(( INTERVAL_DAYS * SECS_PER_DAY ))
    if [ "$_age" -lt "$_interval_secs" ]; then
        CONDITION="FRESH"
        NEXT_DUE_DAYS=$(( (_interval_secs - _age + SECS_PER_DAY - 1) / SECS_PER_DAY ))
    fi
    return 0
}

# >>> cwd_within v1 — keep byte-identical in every hook that has it (hooks/tests/test-path-forms.sh)
# cwd_within <dir>: true when this hook's working directory is <dir> or below it, however either
# side is spelled. One folder can be reached both through a symlink and at its real path, and
# $PWD keeps whichever spelling the session started from; APFS also
# ignores case. So the cwd's ancestors are compared with <dir> as directories (test -ef: same
# device and inode), first along $PWD as spelled (a cwd reached through a symlink inside <dir>
# still counts), then along the resolved path. Builtins only:
# nothing is spawned (this runs on every prompt). <dir> is never handed to cd, so CDPATH cannot
# redirect or print. An empty or missing <dir> never matches. The cwd never changes; $PWD and
# $OLDPWD are restored exactly.
cwd_within() {
    local _cw_dir="$1" _cw_path _cw_pass _cw_pwd="$PWD" _cw_oldpwd="${OLDPWD-}" _cw_rc=1
    [ -n "$_cw_dir" ] || return 1
    case "$PWD/" in "${_cw_dir%/}"/*) return 0 ;; esac      # same spelling: no filesystem access
    [ -d "$_cw_dir" ] || return 1
    for _cw_pass in as-spelled resolved; do
        if [ "$_cw_pass" = resolved ]; then
            CDPATH= cd -P . 2>/dev/null || break                  # same directory, symlinks resolved
            [ "$PWD" != "$_cw_pwd" ] || break                     # nothing to resolve
        fi
        _cw_path="$PWD"
        while :; do
            if [ "$_cw_path" -ef "$_cw_dir" ]; then _cw_rc=0; break 2; fi
            case "$_cw_path" in
                /) break ;;
                /*/*) _cw_path="${_cw_path%/*}" ;;
                *) _cw_path=/ ;;
            esac
        done
    done
    PWD="$_cw_pwd"; OLDPWD="$_cw_oldpwd"
    return "$_cw_rc"
}
# <<< cwd_within v1

in_quiet_dir() {
    # True when the session's cwd is inside one of the colon-separated quiet trees.
    _rest="$QUIET_DIRS"
    while [ -n "$_rest" ]; do
        _dir="${_rest%%:*}"
        case "$_rest" in *:*) _rest="${_rest#*:}" ;; *) _rest="" ;; esac
        [ -n "$_dir" ] || continue
        cwd_within "$_dir" && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# Mode: --write-state "<covered>"
# ---------------------------------------------------------------------------
if [ "$MODE" = "--write-state" ]; then
    if [ -z "${2:-}" ]; then
        echo "NEW-FUNCTIONALITY-CHECK: ERROR --write-state needs the covered string, e.g. --write-state \"2026-w38 / v2.1.290 / 2026-09-22\"" >&2
        exit 1
    fi
    # `covered` is echoed into every future session's context, so it is reduced
    # to a plain charset and a short length before it is stored.
    _not_plain='[!A-Za-z0-9 ._/:+,-]'
    _covered="${2//$_not_plain/}"
    _covered="${_covered:0:$COVERED_MAX_CHARS}"
    read_clock
    _utc="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
    if ! write_state_file "$NOW" "$_utc" 0 0 "$_covered"; then
        echo "NEW-FUNCTIONALITY-CHECK: ERROR could not write $STATE_FILE — the sweep is NOT recorded and the notice will fire again" >&2
        exit 1
    fi
    # Read back: a write that silently produced something unparseable is a failure too.
    read_state
    if [ "$LAST_RUN_EPOCH" != "$NOW" ]; then
        echo "NEW-FUNCTIONALITY-CHECK: ERROR $STATE_FILE did not read back as written — the sweep is NOT recorded" >&2
        exit 1
    fi
    echo "NEW-FUNCTIONALITY-CHECK: sweep recorded -> $STATE_FILE (covered: $_covered)" >&2
    exit 0
fi

# ---------------------------------------------------------------------------
# Mode: --status (no side effects)
# ---------------------------------------------------------------------------
if [ "$MODE" = "--status" ]; then
    read_state
    read_clock
    read_installed_version
    compute_condition
    if [ "${CLAUDE_NEW_FUNCTIONALITY_CHECK:-1}" = "0" ]; then
        echo "WARNING: notices are OPTED OUT on this machine (CLAUDE_NEW_FUNCTIONALITY_CHECK=0) — a sweep only happens when someone runs /claude-code-new-functionality-check by hand."
    fi
    case "$CONDITION" in
        DORMANT) echo "DORMANT: no ledger directory at $LEDGER_DIR — this machine has not opted in to release sweeps (mkdir it to make this machine the designated sweeper)." ;;
        NEVER)   echo "NEVER-RUN: no ledger at $LEDGER_DIR — the first sweep on this machine is a backfill: a full one, or a shorter 'backfill since <week>' (ask the user first)." ;;
        DUE)     echo "DUE: last sweep $AGE_TEXT (${LAST_RUN_UTC:-no timestamp}); covered: ${COVERED:-unknown}; interval: $INTERVAL_DAYS day(s); reminders since then: $NOTICES_SINCE_LAST_RUN." ;;
        FRESH)   echo "FRESH: last sweep $AGE_TEXT (${LAST_RUN_UTC:-no timestamp}); covered: ${COVERED:-unknown}; next due in about $NEXT_DUE_DAYS day(s)." ;;
    esac
    echo "installed CLI: ${INSTALLED_VERSION:-unknown} · state: $STATE_FILE"
    exit 0
fi

if [ -n "$MODE" ]; then
    echo "NEW-FUNCTIONALITY-CHECK: ERROR unknown mode '$MODE' (expected --status or --write-state \"<covered>\")" >&2
    exit 1
fi

# ===========================================================================
# Default mode: the UserPromptSubmit notice hook. Always exits 0.
# Cheapest exits first: on almost every prompt this ends at FRESH having
# spawned nothing but `date`.
# ===========================================================================

# Opt-out.
[ "${CLAUDE_NEW_FUNCTIONALITY_CHECK:-1}" = "0" ] && exit 0

# No-op inside deliberate headless runs (same convention as sibling hooks).
if [ -n "${CLAUDE_CODE_REVIEW_RECURSION_GUARD:-}" ] || \
   [ -n "${CLAUDE_RUN_TESTS_RECURSION_GUARD:-}" ] || \
   [ -n "${CLAUDE_PROJECT_ORG_RECURSION_GUARD:-}" ] || \
   [ -n "${CLAUDE_CONFLICT_DETECT_RECURSION_GUARD:-}" ] || \
   [ -n "${CLAUDE_AUTO_COMMIT_RECURSION_GUARD:-}" ] || \
   [ -n "${CLAUDE_DEEP_EVAL_RECURSION_GUARD:-}" ]; then
    exit 0
fi

# Not opted in on this machine.
[ -d "$LEDGER_DIR" ] || exit 0

read_state
read_clock
[ "$NOW" -gt 0 ] || exit 0   # no usable clock: stay silent rather than guess
compute_condition
[ "$CONDITION" = "FRESH" ] && exit 0

# Quiet trees speak only once the sweep is badly overdue (and never for an
# unknown age — the notice will reach the user from any other directory).
if in_quiet_dir; then
    [ -n "$AGE_SECS" ] || exit 0
    [ "$AGE_SECS" -ge $(( QUIET_OVERDUE_FACTOR * INTERVAL_DAYS * SECS_PER_DAY )) ] || exit 0
fi

# Speak at most once per renotice window. A negative gap (clock jump) counts as
# "window elapsed" for the same reason a future-dated sweep counts as due.
if [ -n "$LAST_NOTICE_EPOCH" ]; then
    _since=$(( NOW - LAST_NOTICE_EPOCH ))
    if [ "$_since" -ge 0 ] && [ "$_since" -lt "$RENOTICE_SECS" ]; then
        exit 0
    fi
fi

# Subagent prompts are not the user's prompts: a non-empty agent_id in the hook
# payload means this fired inside a subagent, where a notice is pure noise.
# (A prompt that merely mentions agent_id cannot match: inside the JSON string
# its quotes arrive backslash-escaped.) Read last, because nearly every prompt
# has already exited above; `read -d ''` slurps stdin without spawning cat, and
# the timeout means a stdin that never closes can never hang the prompt.
# bash 3.2 caveat: on a timeout, bash 4+ keeps the partial input but 3.2 leaves
# HOOK_INPUT empty, so a stdin slower than the timeout would miss the agent_id
# check and let one stray notice into a subagent. The payload arrives at once in
# practice; do not shorten STDIN_READ_TIMEOUT_SECS without re-testing on 3.2.
HOOK_INPUT=""
if [ ! -t 0 ]; then
    IFS= read -r -t "$STDIN_READ_TIMEOUT_SECS" -d '' HOOK_INPUT || true
fi
case "$HOOK_INPUT" in
    *'"agent_id":"'[!\"]*|*'"agent_id": "'[!\"]*) exit 0 ;;
esac

NOTICES_SINCE_LAST_RUN=$(( NOTICES_SINCE_LAST_RUN + 1 ))
if [ "$CONDITION" = "NEVER" ]; then
    echo "NEW-FUNCTIONALITY-CHECK: no new-functionality-check ledger exists on this machine yet (looked in $LEDGER_DIR). The first sweep is a FULL BACKFILL, a large multi-agent run (millions of tokens), so ask the user before starting it (/claude-code-new-functionality-check backfill), and offer the shorter first pass over recent weeks only (/claude-code-new-functionality-check backfill since <week>). Never start either on your own, and never let it delay their current request."
else
    read_installed_version
    _cli=""
    [ -n "$INSTALLED_VERSION" ] && _cli="; installed CLI now $INSTALLED_VERSION"
    _escalation=""
    if [ "$NOTICES_SINCE_LAST_RUN" -ge "$ESCALATE_AFTER_NOTICES" ]; then
        _escalation=" This is reminder $NOTICES_SINCE_LAST_RUN since the last sweep: either run it this session or tell the user plainly that it keeps being deferred."
    fi
    echo "NEW-FUNCTIONALITY-CHECK: the last Claude Code release sweep on this machine was $AGE_TEXT (covered: ${COVERED:-unknown}$_cli). Finish the user's current request first, then run /claude-code-new-functionality-check at a natural pause (research runs in read-only subagents; a sweep is short when nothing is new, though its research lane still runs) and present any new proposals, or tell the user you are deferring it.$_escalation"
fi

# Hook mode never fails the prompt over an unwritable state file; the only cost
# is that the next prompt repeats the notice.
write_state_file "${LAST_RUN_EPOCH:-0}" "$LAST_RUN_UTC" "$NOW" "$NOTICES_SINCE_LAST_RUN" "$COVERED" || true

exit 0
