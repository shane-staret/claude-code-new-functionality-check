#!/bin/bash
# test-claude-code-new-functionality-check-reminder.sh — offline tests for claude-code-new-functionality-check-reminder.sh
# Verifies: never-run notice (asks before a backfill), due/fresh logic, custom
# interval, renotice debounce, opt-out, headless guards, subagent skip,
# corrupt-state self-heal, --write-state / --status modes (which work even when
# notices are opted out), argument sanitizing, installed-version enrichment,
# exit 0 everywhere. No network and no sleeping: the clock is injected.
# bash-3.2-safe.

set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/claude-code-new-functionality-check-reminder.sh"
TMPDIR_T="$(mktemp -d /tmp/claude-code-new-functionality-check-test.XXXXXX)"
STATE="$TMPDIR_T/state.json"
LEDGER_DIR="$TMPDIR_T/claude-code-new-functionality-check"
UPDATE_RESULT="$TMPDIR_T/last-update-result.json"
NOW=1800000000
DAY=86400

PASS=0
FAIL=0

run_hook() {
    # run_hook [env assignments or hook args...] — stdin is "{}" unless HOOK_STDIN is set.
    _in="${HOOK_STDIN:-}"
    [ -n "$_in" ] || _in='{}'
    # Pin the quiet dirs (no default exists) so a value set in the user's settings
    # env can never leak in and silence the notices under test.
    printf '%s' "$_in" | env "NEW_FUNCTIONALITY_CHECK_STATE_FILE=$STATE" \
        "CLAUDE_NEW_FUNCTIONALITY_CHECK_QUIET_DIRS=$TMPDIR_T/no-quiet-dir" \
        "CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$LEDGER_DIR" \
        "NEW_FUNCTIONALITY_CHECK_UPDATE_RESULT_FILE=$UPDATE_RESULT" \
        "NEW_FUNCTIONALITY_CHECK_NOW=$NOW" "$@"
}

check() {
    # check <name> <expected> <actual>
    if [ "$2" = "$3" ]; then
        PASS=$((PASS+1)); echo "PASS: $1"
    else
        FAIL=$((FAIL+1)); echo "FAIL: $1 (expected [$2], got [$3])"
    fi
}

check_contains() {
    # check_contains <name> <needle> <haystack>
    case "$3" in
        *"$2"*) PASS=$((PASS+1)); echo "PASS: $1" ;;
        *) FAIL=$((FAIL+1)); echo "FAIL: $1 (expected to contain [$2], got [$3])" ;;
    esac
}

check_absent() {
    # check_absent <name> <needle> <haystack>
    case "$3" in
        *"$2"*) FAIL=$((FAIL+1)); echo "FAIL: $1 (expected NOT to contain [$2], got [$3])" ;;
        *) PASS=$((PASS+1)); echo "PASS: $1" ;;
    esac
}

# 1. Opted-in machine that has never swept (ledger dir exists, no ledger, no state):
#    notice that asks before a backfill.
mkdir -p "$LEDGER_DIR"
OUT=$(run_hook bash "$HOOK")
check_contains "never-run prints a NEW-FUNCTIONALITY-CHECK notice" "NEW-FUNCTIONALITY-CHECK:" "$OUT"
check_contains "never-run notice names the backfill command" "/claude-code-new-functionality-check backfill" "$OUT"
check_contains "never-run notice tells the session to ask the user first" "ask the user" "$OUT"
check_contains "never-run notice offers the shorter first pass" "backfill since <week>" "$OUT"
OUT=$(run_hook bash "$HOOK" --status)
check_contains "--status for a never-run machine offers the shorter first pass too" "backfill since <week>" "$OUT"

write_state() {
    # write_state <last_run_epoch> <last_notice_epoch> <covered>
    printf '{"last_run_epoch": %s, "last_run_utc": "2026-01-01T00:00:00Z", "last_notice_epoch": %s, "covered": "%s"}\n' \
        "$1" "$2" "$3" > "$STATE"
}

# From here on this machine HAS a ledger (it has swept before).
mkdir -p "$LEDGER_DIR"; : > "$LEDGER_DIR/ledger.md"

# 2. Fresh sweep (1 day ago): silent.
write_state $((NOW - DAY)) 0 "2026-w37 / v2.1.278 / 2026-09-15"
OUT=$(run_hook bash "$HOOK")
check "fresh sweep is silent" "" "$OUT"

# 3. Sweep older than the default 7-day interval: due notice with age and coverage.
write_state $((NOW - 8*DAY)) 0 "2026-w37 / v2.1.278 / 2026-09-15"
OUT=$(run_hook bash "$HOOK")
check_contains "stale sweep prints a NEW-FUNCTIONALITY-CHECK notice" "NEW-FUNCTIONALITY-CHECK:" "$OUT"
check_contains "due notice reports the age in days" "8 day(s) ago" "$OUT"
check_contains "due notice reports what was covered" "2026-w37 / v2.1.278 / 2026-09-15" "$OUT"
check_contains "due notice is non-preemptive" "Finish the user's current request first" "$OUT"
check_contains "due notice names the command" "/claude-code-new-functionality-check" "$OUT"
check_contains "due notice offers the defer escape hatch" "deferring" "$OUT"

# 4. Exactly at the interval boundary (7 days) counts as due.
write_state $((NOW - 7*DAY)) 0 "x"
OUT=$(run_hook bash "$HOOK")
check_contains "boundary age is due" "NEW-FUNCTIONALITY-CHECK:" "$OUT"

# 5. State wiped but ledger intact: due, never a re-backfill.
rm -f "$STATE"
OUT=$(run_hook bash "$HOOK")
check_contains "wiped state with a ledger is due" "NEW-FUNCTIONALITY-CHECK:" "$OUT"
case "$OUT" in
    *backfill*) check "wiped state never asks for a backfill" "no-backfill" "mentions backfill" ;;
    *) check "wiped state never asks for a backfill" "no-backfill" "no-backfill" ;;
esac

# 6. Custom interval: a 3-day-old sweep is fresh by default but due at interval 2.
write_state $((NOW - 3*DAY)) 0 "x"
OUT=$(run_hook bash "$HOOK")
check "3-day-old sweep is silent at the default interval" "" "$OUT"
OUT=$(run_hook CLAUDE_NEW_FUNCTIONALITY_CHECK_INTERVAL_DAYS=2 bash "$HOOK")
check_contains "custom interval makes it due" "NEW-FUNCTIONALITY-CHECK:" "$OUT"

# 7. Renotice debounce: once noticed, stay quiet for the window, then speak again —
#    and noticing must never destroy what the skill recorded.
write_state $((NOW - 10*DAY)) 0 "cov-A"
OUT=$(run_hook bash "$HOOK")
check_contains "first due notice fires" "NEW-FUNCTIONALITY-CHECK:" "$OUT"
OUT=$(run_hook bash "$HOOK")
check "second prompt inside the renotice window is silent" "" "$OUT"
check_contains "noticing preserves the covered string" "cov-A" "$(cat "$STATE")"
check_contains "noticing preserves last_run_epoch" "\"last_run_epoch\": $((NOW - 10*DAY))" "$(cat "$STATE")"
OUT=$(run_hook "NEW_FUNCTIONALITY_CHECK_NOW=$((NOW + DAY + 1))" bash "$HOOK")
check_contains "notice returns after the renotice window" "NEW-FUNCTIONALITY-CHECK:" "$OUT"
write_state $((NOW - 10*DAY)) $((NOW - 5)) "cov-A"
OUT=$(run_hook CLAUDE_NEW_FUNCTIONALITY_CHECK_RENOTICE_SECS=0 bash "$HOOK")
check_contains "a renotice window of 0 notices on every prompt" "NEW-FUNCTIONALITY-CHECK:" "$OUT"

# 8. The never-run notice is debounced too (a fresh machine must not nag every turn).
rm -rf "$LEDGER_DIR" "$STATE"; mkdir -p "$LEDGER_DIR"
OUT=$(run_hook bash "$HOOK")
check_contains "never-run notice fires once" "backfill" "$OUT"
OUT=$(run_hook bash "$HOOK")
check "never-run notice is debounced" "" "$OUT"
OUT=$(run_hook "NEW_FUNCTIONALITY_CHECK_NOW=$((NOW + DAY + 1))" bash "$HOOK")
check_contains "never-run notice returns after the window" "backfill" "$OUT"
mkdir -p "$LEDGER_DIR"; : > "$LEDGER_DIR/ledger.md"

# 9. Opt-out is a full no-op (state untouched).
write_state $((NOW - 10*DAY)) 0 "cov-B"
BEFORE="$(cat "$STATE")"
OUT=$(run_hook CLAUDE_NEW_FUNCTIONALITY_CHECK=0 bash "$HOOK")
check "opt-out is silent" "" "$OUT"
check "opt-out leaves state untouched" "$BEFORE" "$(cat "$STATE")"

# 10. Each of the six headless guards is a full no-op.
for G in CLAUDE_CODE_REVIEW_RECURSION_GUARD CLAUDE_RUN_TESTS_RECURSION_GUARD \
         CLAUDE_PROJECT_ORG_RECURSION_GUARD CLAUDE_CONFLICT_DETECT_RECURSION_GUARD \
         CLAUDE_AUTO_COMMIT_RECURSION_GUARD CLAUDE_DEEP_EVAL_RECURSION_GUARD; do
    OUT=$(run_hook "$G=1" bash "$HOOK")
    check "headless guard $G is silent" "" "$OUT"
done
check "headless guards leave state untouched" "$BEFORE" "$(cat "$STATE")"

# 11. Inside a subagent (non-empty agent_id): silent, state untouched.
OUT=$(HOOK_STDIN='{"session_id":"s","hook_event_name":"UserPromptSubmit","agent_id":"agent-abc123","agent_type":"Explore"}' run_hook bash "$HOOK")
check "subagent prompt is silent" "" "$OUT"
OUT=$(HOOK_STDIN='{"session_id":"s", "agent_id": "agent-abc123"}' run_hook bash "$HOOK")
check "subagent prompt (spaced JSON) is silent" "" "$OUT"
check "subagent prompts leave state untouched" "$BEFORE" "$(cat "$STATE")"

# 12. The main thread still notices: an empty agent_id, or a prompt that merely
#     MENTIONS agent_id (its quotes arrive backslash-escaped inside the JSON string).
OUT=$(HOOK_STDIN='{"session_id":"s","agent_id":"","prompt":"hi"}' run_hook bash "$HOOK")
check_contains "empty agent_id is the main thread" "NEW-FUNCTIONALITY-CHECK:" "$OUT"
write_state $((NOW - 10*DAY)) 0 "cov-B"
OUT=$(HOOK_STDIN='{"session_id":"s","prompt":"why does {\"agent_id\":\"x\"} appear?"}' run_hook bash "$HOOK")
check_contains "a prompt that mentions agent_id still notices" "NEW-FUNCTIONALITY-CHECK:" "$OUT"

# 13. Corrupt / empty / future-dated state self-heals into "due" — never a crash, never silence forever.
echo '{"last_run_epoch": "garbage' > "$STATE"
OUT=$(run_hook bash "$HOOK")
check_contains "corrupt state self-heals into a due notice" "NEW-FUNCTIONALITY-CHECK:" "$OUT"
check_contains "self-heal rewrites a well-formed state file" '"last_notice_epoch": ' "$(cat "$STATE")"
: > "$STATE"
OUT=$(run_hook bash "$HOOK")
check_contains "empty state file self-heals" "NEW-FUNCTIONALITY-CHECK:" "$OUT"
write_state $((NOW + 30*DAY)) 0 "cov-C"
OUT=$(run_hook bash "$HOOK")
check_contains "a future-dated sweep is treated as due" "NEW-FUNCTIONALITY-CHECK:" "$OUT"
check_contains "a future-dated sweep explains itself" "in the future" "$OUT"

# 14. --write-state records a sweep: the hook is silent afterwards.
write_state $((NOW - 10*DAY)) 0 "old"
run_hook bash "$HOOK" --write-state "2026-w38 / v2.1.290 / 2026-09-22" >/dev/null 2>&1
check "--write-state exits 0" "0" "$?"
check_contains "--write-state stores the covered string" '"covered": "2026-w38 / v2.1.290 / 2026-09-22"' "$(cat "$STATE")"
check_contains "--write-state stamps the run time from the clock" "\"last_run_epoch\": $NOW," "$(cat "$STATE")"
OUT=$(run_hook bash "$HOOK")
check "hook is silent right after a recorded sweep" "" "$OUT"

# 15. --write-state sanitizes its argument so the one-line JSON can never be corrupted.
run_hook bash "$HOOK" --write-state 'w38 "quoted" back\slash' >/dev/null 2>&1
check_contains "quotes and backslashes are stripped from covered" '"covered": "w38 quoted backslash"' "$(cat "$STATE")"
OUT=$(run_hook bash "$HOOK")
check "state written from a hostile argument still parses" "" "$OUT"

# 16. --write-state works even when notices are opted out (a manual sweep must be recorded),
#     and refuses to run without its argument (a silent no-op would hide a skill bug).
rm -f "$STATE"
run_hook CLAUDE_NEW_FUNCTIONALITY_CHECK=0 bash "$HOOK" --write-state "manual" >/dev/null 2>&1
check_contains "an opted-out machine still records a manual sweep" '"covered": "manual"' "$(cat "$STATE" 2>/dev/null)"
run_hook bash "$HOOK" --write-state >/dev/null 2>&1
check "--write-state without an argument exits non-zero" "1" "$?"

# 17. --status is read-only and says what it sees.
write_state $((NOW - 10*DAY)) 0 "cov-D"
BEFORE="$(cat "$STATE")"
OUT=$(run_hook bash "$HOOK" --status)
check_contains "--status reports DUE for a stale sweep" "DUE" "$OUT"
check_contains "--status reports the coverage" "cov-D" "$OUT"
check "--status leaves state untouched" "$BEFORE" "$(cat "$STATE")"
write_state $((NOW - DAY)) 0 "cov-D"
OUT=$(run_hook bash "$HOOK" --status)
check_contains "--status reports FRESH for a recent sweep" "FRESH" "$OUT"
OUT=$(run_hook CLAUDE_NEW_FUNCTIONALITY_CHECK=0 bash "$HOOK" --status)
check_contains "--status says when notices are opted out" "OPTED OUT" "$OUT"
rm -f "$LEDGER_DIR/ledger.md" "$STATE"
OUT=$(run_hook bash "$HOOK" --status)
check_contains "--status reports NEVER-RUN with no ledger" "NEVER-RUN" "$OUT"
: > "$LEDGER_DIR/ledger.md"
OUT=$(run_hook bash "$HOOK" --bogus 2>&1); RC=$?
check "an unknown mode exits non-zero" "1" "$RC"
check_contains "an unknown mode explains itself" "unknown mode" "$OUT"

# 18. The due notice names the installed CLI version when the updater record exists.
printf '{"timestamp":"2026-09-19T06:10:03.263Z","path":"native","outcome":"success","status":"success","version_from":"2.1.274","version_to":"2.1.278","error_code":null}\n' > "$UPDATE_RESULT"
write_state $((NOW - 10*DAY)) 0 "cov-E"
OUT=$(run_hook bash "$HOOK")
check_contains "due notice names the installed CLI version" "installed CLI now 2.1.278" "$OUT"
rm -f "$UPDATE_RESULT"
write_state $((NOW - 10*DAY)) 0 "cov-E"
OUT=$(run_hook bash "$HOOK")
check_contains "a missing updater record is tolerated" "NEW-FUNCTIONALITY-CHECK:" "$OUT"

# 19. Hook mode always exits 0, on every path.
write_state $((NOW - 10*DAY)) 0 "x"; run_hook bash "$HOOK" >/dev/null 2>&1; check "exit 0 when due" "0" "$?"
write_state $((NOW - DAY)) 0 "x";    run_hook bash "$HOOK" >/dev/null 2>&1; check "exit 0 when fresh" "0" "$?"
run_hook CLAUDE_NEW_FUNCTIONALITY_CHECK=0 bash "$HOOK" >/dev/null 2>&1; check "exit 0 when opted out" "0" "$?"
echo 'garbage' > "$STATE"; run_hook bash "$HOOK" >/dev/null 2>&1; check "exit 0 on corrupt state" "0" "$?"
run_hook NEW_FUNCTIONALITY_CHECK_STATE_FILE=/nonexistent-dir/nope/state.json bash "$HOOK" >/dev/null 2>&1
check "exit 0 when the state file cannot be written" "0" "$?"

# 20. Policy hygiene: the hook never spawns a headless session (SH5, ADR 0008).
if grep -nE 'claude[[:space:]]+-p' "$HOOK" | grep -vE '^[0-9]+:[[:space:]]*#' >/dev/null; then
    check "no headless invocation on a non-comment line" "absent" "present"
else
    check "no headless invocation on a non-comment line" "absent" "absent"
fi

# 21. A sweep that cannot be recorded must be LOUD (the skill relies on --write-state).
run_hook NEW_FUNCTIONALITY_CHECK_STATE_FILE=/nonexistent-dir/nope/state.json bash "$HOOK" --write-state "x" >/dev/null 2>&1
check "--write-state exits non-zero when the state file cannot be written" "1" "$?"

# 22. Opt-in per machine: with NO ledger directory the hook is dormant — a machine that
#     never opted in never nags and never writes state (one designated sweeper per fleet).
rm -rf "$LEDGER_DIR" "$STATE"
OUT=$(run_hook bash "$HOOK")
check "no ledger dir means dormant" "" "$OUT"
if [ -f "$STATE" ]; then check "a dormant hook writes no state" "none" "exists"; else check "a dormant hook writes no state" "none" "none"; fi
OUT=$(run_hook bash "$HOOK" --status)
check_contains "--status explains the dormant state" "DORMANT" "$OUT"
mkdir -p "$LEDGER_DIR"
OUT=$(run_hook bash "$HOOK")
check_contains "opting in (creating the dir) wakes the never-run notice" "backfill" "$OUT"
: > "$LEDGER_DIR/ledger.md"

# 23. Quiet dirs (the client tree): a due sweep stays silent there until it is 2x overdue.
QUIET="$TMPDIR_T/quiet tree"; mkdir -p "$QUIET/sub"
write_state $((NOW - 8*DAY)) 0 "cov-Q"
OUT=$(cd "$QUIET/sub" && run_hook "CLAUDE_NEW_FUNCTIONALITY_CHECK_QUIET_DIRS=/nonexistent:$QUIET" bash "$HOOK")
check "due but inside a quiet dir is silent" "" "$OUT"
write_state $((NOW - 15*DAY)) 0 "cov-Q"
OUT=$(cd "$QUIET/sub" && run_hook "CLAUDE_NEW_FUNCTIONALITY_CHECK_QUIET_DIRS=/nonexistent:$QUIET" bash "$HOOK")
check_contains "a 2x-overdue sweep speaks even inside a quiet dir" "NEW-FUNCTIONALITY-CHECK:" "$OUT"
write_state $((NOW - 8*DAY)) 0 "cov-Q"
OUT=$(cd "$TMPDIR_T" && run_hook "CLAUDE_NEW_FUNCTIONALITY_CHECK_QUIET_DIRS=/nonexistent:$QUIET" bash "$HOOK")
check_contains "outside the quiet dir the notice is normal" "NEW-FUNCTIONALITY-CHECK:" "$OUT"

# 24. Ignored notices escalate: the hook counts how often it has spoken since the last sweep.
write_state $((NOW - 10*DAY)) 0 "cov-N"
run_hook CLAUDE_NEW_FUNCTIONALITY_CHECK_RENOTICE_SECS=0 bash "$HOOK" >/dev/null
run_hook CLAUDE_NEW_FUNCTIONALITY_CHECK_RENOTICE_SECS=0 bash "$HOOK" >/dev/null
OUT=$(run_hook CLAUDE_NEW_FUNCTIONALITY_CHECK_RENOTICE_SECS=0 bash "$HOOK")
check_contains "the third notice since the last sweep says so" "reminder 3" "$OUT"
check_contains "the notice counter is persisted" '"notices_since_last_run": 3' "$(cat "$STATE")"
run_hook bash "$HOOK" --write-state "fresh" >/dev/null 2>&1
check_contains "--write-state resets the notice counter" '"notices_since_last_run": 0' "$(cat "$STATE")"

# 25. covered is charset-whitelisted and length-capped: it is echoed into every future session.
run_hook bash "$HOOK" --write-state 'w38 $(x) `y` <t> ;|& {"k":1} ok' >/dev/null 2>&1
COV="$(sed -n 's/.*"covered": "\(.*\)"}$/\1/p' "$STATE")"
for BAD in '$' '(' ')' '`' '<' '>' ';' '|' '&' '{' '}' '"'; do
    check_absent "covered drops [$BAD]" "$BAD" "$COV"
done
check_contains "covered keeps its plain words" 'w38' "$COV"
check_contains "covered keeps its last plain word" 'ok' "$COV"
LONG="$(printf 'a%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20)"
LONG="$LONG$LONG$LONG$LONG$LONG$LONG$LONG$LONG$LONG$LONG"
run_hook bash "$HOOK" --write-state "$LONG" >/dev/null 2>&1
COVERED_LEN=$(sed -n 's/.*"covered": "\([^"]*\)".*/\1/p' "$STATE" | awk '{ print length($0) }')
check "covered is capped at 120 characters" "120" "$COVERED_LEN"

# 26. --status is loud about an opt-out (a permanent, invisible opt-out is how a watch dies).
write_state $((NOW - DAY)) 0 "cov-S"
OUT=$(run_hook CLAUDE_NEW_FUNCTIONALITY_CHECK=0 bash "$HOOK" --status)
check_contains "--status shouts when notices are opted out" "WARNING" "$OUT"

# 27. A hand-edited number with a leading zero must not reach bash arithmetic as octal
#     ("08" is an invalid octal literal and would abort the computation).
printf '{"last_run_epoch": %s, "last_run_utc": "x", "last_notice_epoch": 0, "notices_since_last_run": 08, "covered": "cov-Z"}\n' "$((NOW - 10*DAY))" > "$STATE"
OUT=$(run_hook bash "$HOOK" 2>"$TMPDIR_T/octal.err"); RC=$?
check_contains "a leading-zero counter still produces the notice" "NEW-FUNCTIONALITY-CHECK:" "$OUT"
check "a leading-zero counter produces no shell error" "" "$(cat "$TMPDIR_T/octal.err")"
check_contains "the counter continues in base 10" '"notices_since_last_run": 9' "$(cat "$STATE")"

# 28-31. A quiet tree spelled two ways (a workspace reached through a symlink and at its real
#        path, with Claude's cwd on the real one). Quiet must mean quiet whichever spelling the
#        session and the setting use, and with no quiet dir set nothing is quiet. Needs real
#        symbolic links.
ICLOUD="$TMPDIR_T/cloud drive/Workspace"
FH="$TMPDIR_T/home"
LINKED="$FH/Documents/Workspace"
mkdir -p "$ICLOUD/clients/example-client" "$ICLOUD/other" "$FH/Documents"
ln -s "$ICLOUD" "$LINKED" 2>/dev/null
if [ -L "$LINKED" ] && [ "$LINKED" -ef "$ICLOUD" ]; then
    RESOLVED="$(cd -P "$ICLOUD" && pwd)"
    write_state $((NOW - 8*DAY)) 0 "cov-P"
    OUT=$(cd "$RESOLVED/clients/example-client" && run_hook "CLAUDE_NEW_FUNCTIONALITY_CHECK_QUIET_DIRS=/nonexistent:$LINKED/clients" bash "$HOOK")
    check "28 quiet dir set through the link, cwd resolved: silent" "" "$OUT"
    write_state $((NOW - 8*DAY)) 0 "cov-P"
    OUT=$(cd "$LINKED/clients/example-client" && run_hook "CLAUDE_NEW_FUNCTIONALITY_CHECK_QUIET_DIRS=$RESOLVED/clients" bash "$HOOK")
    check "29 quiet dir set resolved, cwd through the link: silent" "" "$OUT"
    write_state $((NOW - 8*DAY)) 0 "cov-P"
    OUT=$(cd "$RESOLVED/clients/example-client" && run_hook env -u CLAUDE_NEW_FUNCTIONALITY_CHECK_QUIET_DIRS "HOME=$FH" bash "$HOOK")
    check_contains "30 no quiet dir set (the default is none): even a client tree gets the notice" "NEW-FUNCTIONALITY-CHECK:" "$OUT"
    write_state $((NOW - 8*DAY)) 0 "cov-P"
    OUT=$(cd "$RESOLVED/other" && run_hook env -u CLAUDE_NEW_FUNCTIONALITY_CHECK_QUIET_DIRS "HOME=$FH" bash "$HOOK")
    check_contains "31 no quiet dir set, cwd elsewhere in the workspace: notice" "NEW-FUNCTIONALITY-CHECK:" "$OUT"
else
    echo "SKIP-LOUD: cases 28-31 need real symbolic links (ln -s made a copy here)"
fi

# --- END CASES ---
rm -rf "$TMPDIR_T"
echo "----"
echo "claude-code-new-functionality-check-reminder: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
