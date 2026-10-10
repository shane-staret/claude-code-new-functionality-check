#!/bin/bash
# test-claude-code-new-functionality-check-package.sh — is the package whole and self-consistent?
#
# Hermetic: reads only the package's own files, found relative to this suite
# (hooks/tests/ sits two levels below the folder that holds skills/, agents/ and
# hooks/), so the same file runs in place under ~/.claude and from a fresh clone of
# the public repository. It never reads the user's settings or CLAUDE.md; whether
# the package is WIRED on a machine is a separate, machine-specific check.
#
# Verifies: both agents exist with EXACTLY their intended tool lists (a missing
# tools line inherits every tool, so the comparison fails closed); the skill has
# the Skill Authoring Standard shape; every URL the helper fetches (at least 10) is
# documented in the source registry; every validator length cap (each a number) is
# stated in the agent file that writes the field, and negative controls on fixtures
# prove both comparisons fail when their extraction finds nothing; the installer,
# README and LICENSE ship; every script parses. bash-3.2-safe.

set -u
ROOT="${NEW_FUNCTIONALITY_CHECK_PACKAGE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
NAME="claude-code-new-functionality-check"
SKILL_DIR="$ROOT/skills/$NAME"
SKILL="$SKILL_DIR/SKILL.md"
HELPER="$SKILL_DIR/claude_code_new_functionality_check.sh"
INSTALLER="$SKILL_DIR/install.sh"
EVALUATOR="$ROOT/agents/$NAME-evaluator.md"
RESEARCHER="$ROOT/agents/$NAME-researcher.md"
HOOK="$ROOT/hooks/$NAME-reminder.sh"
SOURCES="$SKILL_DIR/resources/sources.md"
MAX_DESCRIPTION_CHARS=500
MIN_HELPER_URLS=10    # the helper fetches 10 tier-1 URLs today; fewer found means the extraction broke
RESOURCES="references.md testing-$NAME.md applicability-rubric.md ledger-format.md research-agenda.md sources.md tracked-issues.md wiring.md worked-example.md example-report.md"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/$NAME-package-test.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

PASS=0
FAIL=0
check() {
    # check <name> <expected> <actual>
    if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS: $1"; else FAIL=$((FAIL+1)); echo "FAIL: $1 (expected [$2], got [$3])"; fi
}
frontmatter_value() {
    awk -v want="$2" 'NR == 1 && $0 != "---" { exit }
         NR > 1 && $0 == "---" { exit }
         NR > 1 { key = $0; sub(/:.*/, "", key); if (key == want) { value = $0; sub(/^[^:]*:[ \t]*/, "", value); print value; exit } }' "$1" 2>/dev/null
}
yes_no() { if "$@"; then echo yes; else echo no; fi; }

# 1. Every shipped file is present, and every script parses.
for f in "$SKILL" "$HELPER" "$INSTALLER" "$SKILL_DIR/README.md" "$SKILL_DIR/LICENSE" "$EVALUATOR" "$RESEARCHER" "$HOOK"; do
    check "ships ${f#"$ROOT"/}" yes "$(yes_no test -s "$f")"
done
for f in "$HELPER" "$INSTALLER" "$HOOK"; do
    check "${f##*/} parses (bash -n)" yes "$(yes_no bash -n "$f")"
done
check "the helper is executable" yes "$(yes_no test -x "$HELPER")"
check "the installer is executable" yes "$(yes_no test -x "$INSTALLER")"
check "the hook is executable" yes "$(yes_no test -x "$HOOK")"

# 2. Privilege separation is a fact, not a promise: exact tool lists, failing closed.
check "the evaluator can read locally and nothing else"   "Read, Grep, Glob"     "$(frontmatter_value "$EVALUATOR" tools)"
check "the researcher can reach the web and nothing else" "WebSearch, WebFetch"  "$(frontmatter_value "$RESEARCHER" tools)"
check "the evaluator is named for this package"  "$NAME-evaluator"  "$(frontmatter_value "$EVALUATOR" name)"
check "the researcher is named for this package" "$NAME-researcher" "$(frontmatter_value "$RESEARCHER" name)"

# 3. The skill has the Skill Authoring Standard shape.
check "SKILL.md declares its name" "$NAME" "$(frontmatter_value "$SKILL" name)"
DESCRIPTION="$(frontmatter_value "$SKILL" description)"
case "$DESCRIPTION" in "Use when"*) d1=yes ;; *) d1=no ;; esac
check "the description states triggers (starts with 'Use when')" yes "$d1"
case "$DESCRIPTION" in *"Do NOT use"*) d2=yes ;; *) d2=no ;; esac
check "the description carries a negative scope" yes "$d2"
if [ "${#DESCRIPTION}" -gt 0 ] && [ "${#DESCRIPTION}" -le "$MAX_DESCRIPTION_CHARS" ]; then d3=yes; else d3="no (${#DESCRIPTION})"; fi
check "the description fits in $MAX_DESCRIPTION_CHARS characters" yes "$d3"
for RESOURCE in $RESOURCES; do
    check "resource $RESOURCE exists" yes "$(yes_no test -s "$SKILL_DIR/resources/$RESOURCE")"
    if grep -q -F "resources/$RESOURCE" "$SKILL" 2>/dev/null; then r=yes; else r=no; fi
    check "SKILL.md lists resources/$RESOURCE in its Resources table" yes "$r"
done
if find "$SKILL_DIR" -type d -name archive 2>/dev/null | grep -q .; then a=found; else a=none; fi
check "no archive/ dir inside the skill" none "$a"

# Checks 4 and 5 compare lists extracted from the helper. Each runs as a function of its input
# files, so the suite can prove on fixtures that an extraction which finds nothing FAILS: a
# renamed variable or caps table must never turn the comparison into a vacuous pass.
fails_or_passes() { if [ -n "$1" ]; then echo fails; else echo passes; fi; }

# 4. The registry documents what the helper actually fetches.
helper_urls() {
    # helper_urls <helper> -> the default URL of every NEW_FUNCTIONALITY_CHECK_URL_* setting, one per line
    grep -o 'NEW_FUNCTIONALITY_CHECK_URL_[A-Z_]*:-https://[^}]*' "$1" 2>/dev/null | sed 's/^[^-]*-//'
}
registry_gaps() {
    # registry_gaps <helper> <sources.md> -> each URL the registry does not document; nothing when all
    # are. Finding fewer than MIN_HELPER_URLS URLs in the helper is a gap in itself.
    local urls url count
    urls="$(helper_urls "$1")"
    count="$(printf '%s' "$urls" | grep -c .)"
    [ "$count" -ge "$MIN_HELPER_URLS" ] \
        || printf ' only %s URL(s) found in %s, expected at least %s' "$count" "${1##*/}" "$MIN_HELPER_URLS"
    for url in $urls; do
        grep -q -F -- "$url" "$2" 2>/dev/null || printf ' %s' "$url"
    done
}
check "every URL the helper fetches is documented in sources.md" "" "$(registry_gaps "$HELPER" "$SOURCES")"
printf 'URL_INDEX="${RENAMED_URL_INDEX:-https://example.com/whats-new.md}"\n' > "$SANDBOX/helper-renamed.sh"
check "the registry check fails when the helper yields no URLs" fails \
    "$(fails_or_passes "$(registry_gaps "$SANDBOX/helper-renamed.sh" "$SOURCES")")"
FIRST_URL="$(helper_urls "$HELPER" | head -1)"
grep -v -F -- "${FIRST_URL:-no-url-found}" "$SOURCES" > "$SANDBOX/sources-missing-one.md"
check "the registry check fails when sources.md misses one URL" fails \
    "$(fails_or_passes "$(registry_gaps "$HELPER" "$SANDBOX/sources-missing-one.md")")"

# 5. The agent files and the validator agree: no agent is told to emit a field the
#    validator rejects, and every length cap the validator enforces is stated in the
#    file of the agent that writes that field (a cap an agent cannot see is no contract).
if grep -q -F 'report it in `header.notes`' "$EVALUATOR" 2>/dev/null; then n=present; else n=absent; fi
check "the evaluator is never told to write header.notes (the validator rejects it)" absent "$n"
cap_gaps() {
    # cap_gaps <helper> <agent file> <label> <field...> -> each field whose cap the agent file does not
    # state. A cap that is not a number in the helper's table is a gap too: compared as "" it would
    # match any "<field> <= " in the agent file.
    local helper="$1" agent="$2" label="$3" field cap
    shift 3
    for field in "$@"; do
        cap="$(grep -o "\"$field\": [0-9]*" "$helper" 2>/dev/null | head -1 | sed 's/.*: //')"
        # The field must stand alone: "by_quote <= 300" does not state the cap of "quote".
        case "$cap" in
            ''|*[!0-9]*) printf ' %s:%s(no numeric cap in the helper)' "$label" "$field" ;;
            *) grep -q -E -- "(^|[^A-Za-z0-9_])$field <= $cap([^0-9]|\$)" "$agent" 2>/dev/null || printf ' %s:%s<=%s' "$label" "$field" "$cap" ;;
        esac
    done
}
EVALUATOR_FIELDS="title feature_key quote today proposed_change verify_before_adopting reason_if_no_action slice capability why url docs_url source ref version"
RESEARCHER_FIELDS="title feature_key quote claim proposed_change by_quote url by_url reason"
UNSTATED="$(cap_gaps "$HELPER" "$EVALUATOR" evaluator $EVALUATOR_FIELDS)"
UNSTATED="$UNSTATED$(cap_gaps "$HELPER" "$RESEARCHER" researcher $RESEARCHER_FIELDS)"
check "every validator length cap is stated in the agent file that writes the field" "" "$UNSTATED"
# The two lists above are checked against the helper's caps table itself, so a new cap cannot be
# added without saying which agent writes the field.
UNASSIGNED=""
for field in $(grep '^FIELD_CAPS_JSON=' "$HELPER" | grep -o '"[a-z_]*": [0-9]*' | sed 's/"\([a-z_]*\)".*/\1/'); do
    case " $EVALUATOR_FIELDS $RESEARCHER_FIELDS " in *" $field "*) ;; *) UNASSIGNED="$UNASSIGNED $field" ;; esac
done
check "every capped field in the helper is assigned to the agent that writes it" "" "$UNASSIGNED"
printf '{"titel": 160}\n' > "$SANDBOX/helper-caps-renamed.sh"
check "the cap check fails when the helper's caps table yields no number" fails \
    "$(fails_or_passes "$(cap_gaps "$SANDBOX/helper-caps-renamed.sh" "$EVALUATOR" evaluator title)")"
printf '{"quote": 300}\n' > "$SANDBOX/helper-caps-quote.sh"
printf 'by_quote <= 300\n' > "$SANDBOX/agent-states-by-quote-only.md"
check "the cap check fails when only a longer field name states the cap (by_quote is not quote)" fails \
    "$(fails_or_passes "$(cap_gaps "$SANDBOX/helper-caps-quote.sh" "$SANDBOX/agent-states-by-quote-only.md" evaluator quote)")"
printf 'quote <= 3000\n' > "$SANDBOX/agent-states-a-longer-cap.md"
check "the cap check fails when only a longer number states the cap (3000 is not 300)" fails \
    "$(fails_or_passes "$(cap_gaps "$SANDBOX/helper-caps-quote.sh" "$SANDBOX/agent-states-a-longer-cap.md" evaluator quote)")"

# 6. The new-capability lens is wired end to end: the rubric defines it, the skill lists launches
#    and checks completeness, and the evaluator is told to account for every launch.
RUBRIC="$SKILL_DIR/resources/applicability-rubric.md"
if grep -q -F '## The new-capability lens' "$RUBRIC" 2>/dev/null; then l1=yes; else l1=no; fi
check "the rubric defines the new-capability lens" yes "$l1"
if grep -q -F 'launches --record' "$SKILL" 2>/dev/null && grep -q -F -- '--launches' "$SKILL" 2>/dev/null; then l2=yes; else l2=no; fi
check "SKILL.md lists launches, checks completeness (--launches) and records only validated results" yes "$l2"
if grep -q -F 'dispositions' "$EVALUATOR" 2>/dev/null && grep -q -F 'LENS: new-capability' "$EVALUATOR" 2>/dev/null; then l3=yes; else l3=no; fi
check "the evaluator is told to give every launch a disposition under LENS: new-capability" yes "$l3"
# The lens's enums come from the helper; the evaluator must name every value the validator accepts.
ENUM_GAPS=""
for value in $(grep -E '^(BREADTHS|DISPOSITION_CLASSES)=' "$HELPER" | sed 's/^[A-Z_]*="\([^"]*\)".*/\1/'); do
    grep -q -E -- "(^|[^a-z-])$value([^a-z-]|\$)" "$EVALUATOR" 2>/dev/null || ENUM_GAPS="$ENUM_GAPS $value"
done
check "the evaluator names every breadth and disposition class the validator accepts" "" "$ENUM_GAPS"
if [ "$(grep -E -c '^(BREADTHS|DISPOSITION_CLASSES)=' "$HELPER")" = 2 ]; then e=found; else e=missing; fi
check "the helper still defines both lens enums (the check above is not vacuous)" found "$e"

echo "----"
echo "claude-code-new-functionality-check-package: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
