#!/usr/bin/env bash
# claude_code_new_functionality_check.sh — deterministic half of the /claude-code-new-functionality-check skill.
#
# The skill's judgment (what a release means for THIS config) belongs to the
# model. Everything that must be exact and repeatable lives here instead: which
# digests are new, which changelog versions are new, what changed on a watched
# page, what the config actually contains. A model re-deriving those each week
# would drift; a tested script does not.
#
# Usage:
#   claude_code_new_functionality_check.sh digests [<index-file>]        slug|label|dates|versions per weekly digest
#   claude_code_new_functionality_check.sh new-digests <slug|none> [<index-file>]
#                                                  digests strictly newer than <slug>
#   claude_code_new_functionality_check.sh changelog-since <version> [<until-version>] [--no-fixed] [--file <path>]
#                                                  changelog sections newer than <version>
#                                                  (and <= <until-version>), normalized to
#                                                  "## X.Y.Z (date)" + "- " bullets
#   claude_code_new_functionality_check.sh fetch                         download every registry source into the cache;
#                                                  prints a per-source table; never clobbers a
#                                                  good cached copy with a failed download
#   claude_code_new_functionality_check.sh watch-diff                    READ-ONLY diff of the watched pages (docs index,
#                                                  best practices, official plugin names) against
#                                                  their snapshots; refuses error pages
#   claude_code_new_functionality_check.sh watch-commit [<name>...]      promote the pending snapshots, or only the named
#                                                  ones (call AFTER the ledger is written, never before)
#   claude_code_new_functionality_check.sh launches [--since <date> [--until <date>]]
#                                                  READ-ONLY list of launches (digest features, support-notes
#                                                  entries, new docs pages) for the new-capability lens: the
#                                                  unseen ones of the last 60 days, or a dated catch-up window
#   claude_code_new_functionality_check.sh launches --record <slice> <result.json>
#                                                  add a slice's launches to the seen-set (.pending) once its
#                                                  result is complete for that slice and its quotes verify
#   claude_code_new_functionality_check.sh launches --rebaseline-docs
#                                                  take every current docs page as seen (.pending), after the
#                                                  docs index was reorganized
#   claude_code_new_functionality_check.sh tracked-issues [--file <p>]   issue|keywords|workaround rows of the tracked table
#   claude_code_new_functionality_check.sh issue-status <n>              #n | state | state_reason | closed_at | title
#   claude_code_new_functionality_check.sh issue-evidence <n>            every changelog bullet (Fixed included) that
#                                                  mentions a tracked issue's keywords
#   claude_code_new_functionality_check.sh verify-quote <file> <quote>   0 if the quote is verbatim in the file
#   claude_code_new_functionality_check.sh verify-candidates <results.json> <slice-file>...
#                                                  verify-quote for every PROPOSE / RISK-WATCH in
#                                                  an evaluator result (exit 1 if any quote fails)
#   claude_code_new_functionality_check.sh verify-lead <url> <quote>     fetch an OFFICIAL https page and verify the
#                                                  quote against it (0 yes, 1 no, 2 fetch failed)
#   claude_code_new_functionality_check.sh scrub-check <agenda-file>     refuse a research agenda that carries private terms
#   claude_code_new_functionality_check.sh save-result <out.json> [<transcript.jsonl>]
#                                                  recover a subagent's JSON reply from its transcript
#                                                  (the <output-file> of its task notification), or
#                                                  from pasted notification text on stdin
#   claude_code_new_functionality_check.sh validate-candidates <evaluator|researcher> <file> [--launches <slice>]
#                                                  schema check of subagent output: structure is strict;
#                                                  a field up to 2x its length cap is only flagged OVERLONG;
#                                                  --launches: a new-capability result must give every
#                                                  launch in <slice> exactly one disposition
#   claude_code_new_functionality_check.sh inventory                     generated snapshot of the real config
#   claude_code_new_functionality_check.sh ledger-add <curated.json>     render curated PROPOSE / RISK-WATCH candidates
#                                                  into ledger.md + proposals.md with fresh ids
#   claude_code_new_functionality_check.sh ledger-status <RW-id> <status> [<detail>]
#                                                  record a decision: index row and detail block change
#                                                  together or not at all (declined needs a why,
#                                                  deferred an until, applied its evidence)
#   claude_code_new_functionality_check.sh next-id | snapshot | ledger-check | lock | unlock
#                                                  ledger bookkeeping
#   claude_code_new_functionality_check.sh backup [<dir>]                dated tar.gz of the ledger OFF this disk; the target is
#                                                  <dir>, else BACKUP_DIR= in <ledger>/backup.conf
#
# Exit: 0 = ok
#       1 = usage or precondition error (bad argument, missing input file)
#       2 = one or more sources failed (partial result — coverage must not advance),
#           or `backup` could not write its archive
#       3 = parse error: a source's format drifted (NEVER report this as "nothing new")

set -uo pipefail
export LC_ALL=C
export PYTHONIOENCODING=utf-8

# ---------------------------------------------------------------- configuration
CACHE_DIR="${NEW_FUNCTIONALITY_CHECK_CACHE_DIR:-$HOME/.claude/tmp/claude-code-new-functionality-check/cache}"
INDEX_FILE_NAME="whats-new.md"
CHANGELOG_FILE_NAME="changelog.md"
DIGEST_DIR_NAME="digests"
ALWAYS_REFETCH_NEWEST_DIGESTS=2      # a just-published digest is still being edited upstream

# Tier-1 sources (resources/sources.md documents them; the package suite checks the two agree).
URL_INDEX="${NEW_FUNCTIONALITY_CHECK_URL_INDEX:-https://code.claude.com/docs/en/whats-new.md}"
URL_DIGEST_BASE="${NEW_FUNCTIONALITY_CHECK_URL_DIGEST_BASE:-https://code.claude.com/docs/en/whats-new}"
URL_CHANGELOG="${NEW_FUNCTIONALITY_CHECK_URL_CHANGELOG:-https://code.claude.com/docs/en/changelog.md}"
URL_CHANGELOG_MIRROR="${NEW_FUNCTIONALITY_CHECK_URL_CHANGELOG_MIRROR:-https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md}"
LOCAL_CHANGELOG="${NEW_FUNCTIONALITY_CHECK_LOCAL_CHANGELOG:-$HOME/.claude/cache/changelog.md}"
URL_DOCS_INDEX="${NEW_FUNCTIONALITY_CHECK_URL_DOCS_INDEX:-https://code.claude.com/docs/llms.txt}"
URL_BEST_PRACTICES="${NEW_FUNCTIONALITY_CHECK_URL_BEST_PRACTICES:-https://code.claude.com/docs/en/best-practices.md}"
URL_MARKETPLACE="${NEW_FUNCTIONALITY_CHECK_URL_MARKETPLACE:-https://raw.githubusercontent.com/anthropics/claude-plugins-official/main/.claude-plugin/marketplace.json}"
URL_NPM_LATEST="${NEW_FUNCTIONALITY_CHECK_URL_NPM_LATEST:-https://registry.npmjs.org/@anthropic-ai/claude-code/latest}"
URL_SUPPORT_NOTES="${NEW_FUNCTIONALITY_CHECK_URL_SUPPORT_NOTES:-https://support.claude.com/en/articles/12138966-release-notes}"
# A redirect may only ever land on an official host.
ALLOWED_HOSTS=" code.claude.com raw.githubusercontent.com registry.npmjs.org api.github.com support.claude.com www.anthropic.com anthropic.com claude.com www.claude.com github.com "

# Bounded-backoff policy (Retry & Resilience Standard section 3). macOS has no
# `timeout` binary, so curl's own --connect-timeout/--max-time are the per-attempt
# timeout, and DEADLINE_SECS is the overall one. No attempt STARTS and no backoff
# is slept past it, so the worst case is DEADLINE_SECS + MAX_TIME (270s) — below the
# 300s the skill gives the Bash tool, so the per-source table always prints (ACCOUNT duty).
RETRY_ATTEMPTS="${NEW_FUNCTIONALITY_CHECK_RETRY_ATTEMPTS:-4}"
RETRY_BASE_SECS="${NEW_FUNCTIONALITY_CHECK_RETRY_BASE_SECS:-2}"
RETRY_CAP_SECS=30
CONNECT_TIMEOUT="${NEW_FUNCTIONALITY_CHECK_CONNECT_TIMEOUT:-10}"
MAX_TIME="${NEW_FUNCTIONALITY_CHECK_MAX_TIME:-30}"
DEADLINE_SECS="${NEW_FUNCTIONALITY_CHECK_DEADLINE_SECS:-240}"
MAX_FILESIZE_BYTES=5000000
CURL_PROTO="${NEW_FUNCTIONALITY_CHECK_CURL_PROTO:-=https}"     # tests widen this to reach file:// fixtures
VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$'
AWK_NO_VERSIONS_SEEN=9

EXIT_USAGE=1
EXIT_PARTIAL=2
EXIT_PARSE=3

# Where things live. The ledger is per-machine and outside the shipped config set,
# so a config deploy can never overwrite the user's decision history.
LEDGER_DIR="${CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR:-$HOME/.claude/claude-code-new-functionality-check}"
CLAUDE_DIR="${NEW_FUNCTIONALITY_CHECK_CLAUDE_DIR:-$HOME/.claude}"
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
# The upstream issues a config works around are per-machine, so their table lives beside the
# ledger; the skill ships an empty template for a machine that tracks none.
if [ -f "$LEDGER_DIR/tracked-issues.md" ]; then
    TRACKED_ISSUES_FILE="$LEDGER_DIR/tracked-issues.md"
else
    TRACKED_ISSUES_FILE="$SKILL_DIR/resources/tracked-issues.md"
fi
URL_ISSUE_API_BASE="${NEW_FUNCTIONALITY_CHECK_URL_ISSUE_API_BASE:-https://api.github.com/repos/anthropics/claude-code/issues}"
SNAPSHOT_DIR_NAME="snapshots"
LEDGER_FILES="ledger.md proposals.md no-action.md leads.md backlog.md"
# Off-disk backup: the ledger dir is outside the shipped config and every other backup, and
# `snapshot` only makes same-disk copies. The same-disk archive/ is left out of the tarball.
BACKUP_CONF_NAME="backup.conf"
BACKUP_FILE_PREFIX="claude_code_new_functionality_check_ledger_"
BACKUP_EXCLUDED_DIR="archive"
BACKUP_MAX_NAME_TRIES=50
STATUS_VOCABULARY="proposed accepted declined deferred applied obsolete"
# Field length caps (characters) — ONE table for both gates, and the package suite checks
# that each agent file states the caps of the fields it writes. validate-candidates is
# SOFT up to OVERLONG_FACTOR x the cap (the field is flagged: reword it while curating,
# never log it verbatim) and rejects the whole result beyond that; ledger-add is HARD at
# the cap, so nothing over-long can reach the ledger.
FIELD_CAPS_JSON='{"title": 160, "feature_key": 80, "quote": 300, "by_quote": 300, "today": 1200, "proposed_change": 1200, "verify_before_adopting": 600, "reason_if_no_action": 400, "claim": 900, "url": 500, "docs_url": 500, "by_url": 500, "source": 40, "ref": 60, "version": 40, "slice": 400, "reason": 300, "capability": 600, "why": 300}'
OVERLONG_FACTOR=2
# The new-capability lens (see cmd_launches). Breadth says how much of the system a launch
# would change; every launch in a slice gets exactly one disposition class.
BREADTHS="system several one"
DISPOSITION_CLASSES="new-capability iteration no-fit"
LAUNCHES_SEEN_NAME="launches-seen"   # snapshots/<name>.txt, promoted by watch-commit like the watched pages
LAUNCH_LOOKBACK_DAYS="${NEW_FUNCTIONALITY_CHECK_LAUNCH_LOOKBACK_DAYS:-60}"   # a weekly listing covers this many days
LAUNCH_SLICE_MAX="${NEW_FUNCTIONALITY_CHECK_LAUNCH_SLICE_MAX:-50}"           # the most launches one slice may hold
LAUNCHES_SLICE_MARKER="# Launches · slice-id"                                # how every launches slice begins
# One definition of an official URL for every python reader (launches, the validator, the quote
# verifier): https, no userinfo, no whitespace or markup characters; the host is then checked, as
# text, against ALLOWED_HOSTS.
OFFICIAL_URL_PATTERN='^https://([^/@:\s|`"<>]+)(?::\d+)?(?:[/?#][^\s|`"<>]*)?$'
LOCK_STALE_SECS="${NEW_FUNCTIONALITY_CHECK_LOCK_STALE_SECS:-7200}"
# verify-lead reuses a page it fetched this recently instead of fetching it once per quote:
# several leads usually cite the same docs page, and back-to-back refetches trip rate limits.
LEAD_CACHE_FRESH_SECS="${NEW_FUNCTIONALITY_CHECK_LEAD_CACHE_FRESH_SECS:-3600}"

# Fetch classification (see classify_fetch).
CURL_TRANSIENT_EXITS=" 5 6 7 18 28 35 52 55 56 "   # resolve/connect/partial/timeout/TLS/empty/send/recv
RATE_LIMITED_HOST="api.github.com"                  # its 403/429 mean "quota", not "forbidden"

# Watched pages and their sanity floors (see cmd_watch_diff).
WATCHED_PAGES="docs-index best-practices marketplace"
FLOOR_DOCS_INDEX="${NEW_FUNCTIONALITY_CHECK_FLOOR_DOCS_INDEX:-50}"          # real index: ~200 entries
FLOOR_BEST_PRACTICES="${NEW_FUNCTIONALITY_CHECK_FLOOR_BEST_PRACTICES:-50}"  # real page: ~400 lines
FLOOR_MARKETPLACE="${NEW_FUNCTIONALITY_CHECK_FLOOR_MARKETPLACE:-50}"        # real manifest: ~300 plugins
MAX_SHRINK_PERCENT=50     # a page that loses more than this is an error page, not an update
WATCH_DIFF_MAX_LINES=200  # rendered changed lines per page; the summary line always counts them all

# Verification, scrubbing, inventory.
MIN_QUOTE_CHARS=20
MIN_SCRUB_TERM_CHARS=4
ABSENT_FEATURE_PATHS="rules commands workflows output-styles keybindings.json"

# The header comment IS the usage text: everything from line 2 up to the first
# blank line, with the comment markers removed.
print_usage() { awk 'NR > 1 && /^$/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; }

# The day a run counts as today, in UTC; overridable so the offline suites can pin it.
today_utc() { emit "${NEW_FUNCTIONALITY_CHECK_TODAY:-$(date -u +%Y-%m-%d)}"; }

emit() { printf '%s\n' "$*"; }
warn() { printf 'claude-code-new-functionality-check: WARNING %s\n' "$*" >&2; }
die()  { printf 'claude-code-new-functionality-check: ERROR %s\n' "$2" >&2; exit "$1"; }

# ------------------------------------------------------------------ index parsing
# The What's New index is Mintlify MDX: one <Update label="Week N" description=
# "<dates>" tags={["<versions>"]}> block per week, each linking to its digest at
# /docs/en/whats-new/<year>-w<week>.
parse_index() {
    # parse_index <file> -> "slug|label|dates|versions" per digest, in page order
    awk '
    /^<Update label=/ {
        label = $0; sub(/^<Update label="/, "", label); sub(/".*/, "", label)
        dates = $0; sub(/.*description="/, "", dates);  sub(/".*/, "", dates)
        vers  = $0; sub(/.*tags=\{\["/, "", vers);      sub(/"\]\}.*/, "", vers)
    }
    /\(\/docs\/en\/whats-new\/[0-9]+-w[0-9]+\)/ {
        slug = $0; sub(/.*\/docs\/en\/whats-new\//, "", slug); sub(/\).*/, "", slug)
        print slug "|" label "|" dates "|" vers
    }' "$1"
}

require_index() {
    # require_index <file> — missing input is a precondition error, never an empty result.
    [ -f "$1" ] || die "$EXIT_USAGE" "index file not found: $1 (run: claude_code_new_functionality_check.sh fetch)"
}

cmd_digests() {
    local file="${1:-$CACHE_DIR/$INDEX_FILE_NAME}" parsed
    require_index "$file"
    parsed="$(parse_index "$file")"
    if [ -z "$parsed" ] && [ -s "$file" ]; then
        die "$EXIT_PARSE" "parse error: $file is not empty but no weekly digest could be parsed — the What's New page format has drifted; fix parse_index before trusting any result"
    fi
    [ -n "$parsed" ] && emit "$parsed"
    return 0
}

cmd_new_digests() {
    local since="${1:-}" file="${2:-$CACHE_DIR/$INDEX_FILE_NAME}" parsed
    case "$since" in
        none) since="0-w0" ;;
        [0-9]*-w[0-9]*) ;;
        *) die "$EXIT_USAGE" "new-digests needs a slug like 2026-w37, or 'none' (got: '${since}')" ;;
    esac
    parsed="$(cmd_digests "$file")" || exit $?
    # Week numbers are not zero-padded upstream (2027-w9), so order is decided
    # numerically on (year, week) — a string compare would call 2026-w9 newer
    # than 2026-w37.
    printf '%s\n' "$parsed" | awk -F'|' -v since="$since" '
        function key(slug,  part) { split(slug, part, "-w"); return part[1] * 100 + part[2] }
        BEGIN { floor = key(since) }
        $1 != "" && key($1) > floor { print $1 }'
}

# -------------------------------------------------------------- changelog slicing
is_version() { printf '%s' "$1" | grep -Eq "$VERSION_PATTERN"; }

# Upstream publishes the changelog in two shapes, and the fallback chain can land
# on either, so one parser accepts both:
#   docs mirror     <Update label="2.1.278" description="September 19, 2026"> ... </Update>
#   GitHub raw and the CLI's local cache     ## 2.1.278
# Versions are compared numerically field by field, and never assumed contiguous
# (upstream skips numbers). POSIX character classes are avoided inside awk: the
# Raspberry Pi's mawk has historically lacked them.
slice_changelog() {
    # slice_changelog <file> <since> <upto-or-empty> <drop_fixed 0|1>
    awk -v since="$2" -v upto="$3" -v drop_fixed="$4" -v none_seen="$AWK_NO_VERSIONS_SEEN" '
    function vnum(v,  part) { split(v, part, "."); return part[1] * 100000000 + part[2] * 10000 + part[3] }
    function wanted(v) { return vnum(v) > floor && (ceiling < 0 || vnum(v) <= ceiling) }
    BEGIN { floor = vnum(since); ceiling = (upto == "" ? -1 : vnum(upto)); keep = 0; seen = 0 }
    /^<Update label="[0-9]+\.[0-9]+\.[0-9]+"/ {
        v = $0; sub(/^<Update label="/, "", v); sub(/".*/, "", v)
        d = $0; sub(/.*description="/, "", d);  sub(/".*/, "", d)
        seen++; keep = wanted(v)
        if (keep) print "## " v " (" d ")"
        next
    }
    /^## [0-9]+\.[0-9]+\.[0-9]+[ \t]*$/ {
        v = $2; seen++; keep = wanted(v)
        if (keep) print "## " v
        next
    }
    /^<\/Update>/ { if (keep) print ""; next }
    !keep { next }
    {
        line = $0
        sub(/^[ \t]*[*-][ \t]+/, "- ", line)
        if (drop_fixed == 1 && line ~ /^- Fixed/) next
        print line
    }
    END { if (seen == 0) exit none_seen }' "$1"
}

cmd_changelog_since() {
    local since="" upto="" drop_fixed=0 file="$CACHE_DIR/$CHANGELOG_FILE_NAME" sliced rc
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-fixed) drop_fixed=1 ;;
            --file)     shift; file="${1:-}" ;;
            *)
                if [ -z "$since" ]; then since="$1"
                elif [ -z "$upto" ]; then upto="$1"
                else die "$EXIT_USAGE" "changelog-since takes at most two versions (extra argument: $1)"
                fi ;;
        esac
        shift
    done
    is_version "$since" || die "$EXIT_USAGE" "changelog-since needs a version like 2.1.269 (got: '${since}')"
    [ -z "$upto" ] || is_version "$upto" || die "$EXIT_USAGE" "the upper bound must be a version like 2.1.277 (got: '${upto}')"
    [ -f "$file" ] || die "$EXIT_USAGE" "changelog file not found: $file (run: claude_code_new_functionality_check.sh fetch)"

    sliced="$(slice_changelog "$file" "$since" "$upto" "$drop_fixed")"
    rc=$?
    if [ "$rc" -eq "$AWK_NO_VERSIONS_SEEN" ] && [ -s "$file" ]; then
        die "$EXIT_PARSE" "parse error: $file is not empty but no version heading could be parsed — the changelog format has drifted; fix slice_changelog before trusting any result"
    fi
    [ -n "$sliced" ] && emit "$sliced"
    return 0
}

# ----------------------------------------------------------- fetch classification
# CLASSIFY duty of the Retry & Resilience Standard, as one pure function so that
# every branch is unit-testable offline. The HTTP status decides FIRST and the
# curl exit code only when there is none: measured on macOS, `curl --fail` on a
# plain 404 exits 56 — a "network" code that would otherwise be retried forever.

classify_fetch() {
    # classify_fetch <curl_exit> <http_code> [<host>] -> ok | transient | permanent | rate-limited
    local curl_exit="$1" http_code="$2" host="${3:-}"
    case "$http_code" in
        000)
            # No HTTP status at all: either a non-HTTP scheme that worked (file://
            # fixtures) or a transport-level failure.
            if [ "$curl_exit" -eq 0 ]; then emit ok
            elif [ "${CURL_TRANSIENT_EXITS#* $curl_exit }" != "$CURL_TRANSIENT_EXITS" ]; then emit transient
            else emit permanent
            fi ;;
        2??)
            # A success status with a failed transfer is a truncated body.
            if [ "$curl_exit" -eq 0 ]; then emit ok; else emit transient; fi ;;
        403|429)
            if [ "$host" = "$RATE_LIMITED_HOST" ]; then emit rate-limited
            elif [ "$http_code" = "429" ]; then emit transient
            else emit permanent
            fi ;;
        408)     emit transient ;;
        501)     emit permanent ;;      # "not implemented" never fixes itself
        5??)     emit transient ;;
        *)       emit permanent ;;      # other 4xx and unfollowed 3xx: asking again changes nothing
    esac
}

cmd_classify() {
    [ $# -ge 2 ] || die "$EXIT_USAGE" "_classify needs <curl_exit> <http_code> [<host>]"
    classify_fetch "$@"
}

# ------------------------------------------------------------------- JSON access
# jq where it exists, otherwise a python that can actually import json (on Windows
# `python3` is often the Store stub). Bare sed is never used on API JSON: nested
# objects repeat keys such as "state".
PYTHON_CMD=""
find_python() {
    local candidate
    [ -n "$PYTHON_CMD" ] && return 0
    for candidate in python3 python; do
        if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import json, html.parser' >/dev/null 2>&1; then
            PYTHON_CMD="$candidate"
            return 0
        fi
    done
    return 1
}

json_path() {
    # json_path <file> <path>   e.g. version | state_reason | plugins[].name
    # Prints each leaf on its own line; null/missing prints nothing.
    local file="$1" path="$2" tool="${NEW_FUNCTIONALITY_CHECK_JSON_TOOL:-}"
    if [ -z "$tool" ]; then
        if command -v jq >/dev/null 2>&1; then tool="jq"; else tool="python"; fi
    fi
    if [ "$tool" = "jq" ]; then
        jq -r ".$path // empty" "$file"
        return $?
    fi
    find_python || die "$EXIT_USAGE" "cannot parse JSON on this machine: neither jq nor a working python was found"
    "$PYTHON_CMD" - "$file" "$path" <<'PY'
import json, sys
def walk(node, parts):
    if not parts:
        if node is None:
            return
        if isinstance(node, bool):
            print("true" if node else "false")
        elif isinstance(node, (dict, list)):
            print(json.dumps(node))
        else:
            print(node)
        return
    head, rest = parts[0], parts[1:]
    iterate = head.endswith("[]")
    key = head[:-2] if iterate else head
    if not isinstance(node, dict) or key not in node:
        return
    child = node[key]
    if iterate:
        if isinstance(child, list):
            for item in child:
                walk(item, rest)
    else:
        walk(child, rest)
with open(sys.argv[1], encoding="utf-8") as handle:
    walk(json.load(handle), sys.argv[2].split("."))
PY
}

# ----------------------------------------------------------------- HTML to text
render_html_text() {
    # render_html_text <in.html> <out.txt> — the support release notes are HTML; the
    # evaluator reads (and verify-quote greps) this rendering instead of fetching the page.
    local html="$1" txt="$2"
    if find_python; then
        "$PYTHON_CMD" - "$html" "$txt" <<'PY'
import re, sys
from html.parser import HTMLParser
BLOCK_TAGS = ("p", "div", "h1", "h2", "h3", "h4", "h5", "li", "br", "tr", "section", "article")
HIDDEN_TAGS = ("script", "style", "noscript")
class TextOnly(HTMLParser):
    def __init__(self):
        HTMLParser.__init__(self)
        self.parts, self.hidden = [], 0
    def handle_starttag(self, tag, attrs):
        if tag in HIDDEN_TAGS:
            self.hidden += 1
        if tag in BLOCK_TAGS:
            self.parts.append("\n")
    def handle_endtag(self, tag):
        if tag in HIDDEN_TAGS and self.hidden:
            self.hidden -= 1
    def handle_data(self, data):
        if not self.hidden:
            self.parts.append(data)
parser = TextOnly()
with open(sys.argv[1], encoding="utf-8", errors="replace") as handle:
    parser.feed(handle.read())
text = re.sub(r"[ \t]+", " ", "".join(parser.parts))
text = re.sub(r"\n\s*\n+", "\n", text).strip() + "\n"
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    handle.write(text)
PY
        return $?
    fi
    warn "no working python: rendering $html with a crude tag strip (script bodies may leak into the text)"
    sed -e 's/<[^>]*>/ /g' -e 's/&amp;/\&/g' -e 's/&nbsp;/ /g' -e 's/&quot;/"/g' -e "s/&#x27;/'/g" -e 's/&lt;/</g' -e 's/&gt;/>/g' "$html" \
        | awk 'NF { gsub(/[ \t]+/, " "); print }' > "$txt"
}

# -------------------------------------------------------------------- http_get
url_host() {
    # url_host <url> -> bare host, or empty for URLs that carry userinfo (a spoofing trick)
    local rest="${1#*://}"
    rest="${rest%%/*}"
    case "$rest" in *@*) return 0 ;; esac
    emit "${rest%%:*}"
}

host_allowed() {
    # Only https destinations are held to the allowlist; any other scheme can only
    # be reached when CURL_PROTO was widened on purpose (the offline fixtures).
    local url="$1" host
    case "$url" in
        https://*) ;;
        *) [ "$CURL_PROTO" != "=https" ]; return $? ;;
    esac
    host="$(url_host "$url")"
    [ -n "$host" ] || return 1
    # Quoted inside the pattern so the host is matched as TEXT: unquoted, a host such
    # as "*.com" would be a glob and would match every entry in the allowlist.
    case "$ALLOWED_HOSTS" in *" $host "*) return 0 ;; esac
    return 1
}

cmd_retry_after() {
    [ $# -eq 1 ] || die "$EXIT_USAGE" "_retry-after needs one header file"
    retry_after_secs "$1"
}

cmd_host_allowed() {
    [ $# -eq 1 ] || die "$EXIT_USAGE" "_host-allowed needs one URL"
    host_allowed "$1"
}

START_EPOCH="$(date +%s 2>/dev/null || echo 0)"
deadline_passed() {
    local now
    now="$(date +%s 2>/dev/null || echo 0)"
    [ $(( now - START_EPOCH )) -ge "$DEADLINE_SECS" ]
}

deadline_remaining() {
    local now left
    now="$(date +%s 2>/dev/null || echo 0)"
    left=$(( DEADLINE_SECS - (now - START_EPOCH) ))
    [ "$left" -lt 0 ] && left=0
    printf '%s\n' "$left"
}

retry_after_secs() {
    # retry_after_secs <header-file> -> a server-requested wait in whole seconds, capped; empty if none
    [ -f "$1" ] || return 0
    awk -v cap="$RETRY_CAP_SECS" '
        tolower($1) == "retry-after:" { value = $2; sub(/\r$/, "", value)
            if (value ~ /^[0-9]+$/) { print (value + 0 > cap + 0 ? cap : value); exit } }' "$1"
}

HTTP_GET_DETAIL=""
HTTP_OK=0; HTTP_TRANSIENT=10; HTTP_PERMANENT=11; HTTP_RATE_LIMITED=12; HTTP_DEADLINE=13; HTTP_BAD_HOST=14
http_get() {
    # http_get <url> <dest> — the ONE network wrapper (WRAP duty): bounded attempts,
    # exponential backoff + jitter, Retry-After honored, per-attempt timeout, overall
    # deadline, transient classes only. Downloads to a sibling temp file and renames on
    # success, so a failed fetch can never clobber a good cached copy.
    local url="$1" dest="$2" attempt=1 delay="$RETRY_BASE_SECS" tmp hdr err out curl_exit http_code effective verdict wait_secs asked
    tmp="$dest.part.$$"; hdr="$dest.hdr.$$"; err="$dest.err.$$"
    mkdir -p "$(dirname "$dest")"
    while :; do
        if deadline_passed; then
            rm -f "$tmp" "$hdr" "$err"
            HTTP_GET_DETAIL="overall deadline of ${DEADLINE_SECS}s reached before this source"
            return "$HTTP_DEADLINE"
        fi
        out="$(curl -sS -L --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
                    --max-filesize "$MAX_FILESIZE_BYTES" --proto "$CURL_PROTO" --proto-redir "$CURL_PROTO" \
                    -D "$hdr" -o "$tmp" -w '%{http_code} %{url_effective}' "$url" 2>"$err")"
        curl_exit=$?
        http_code="${out%% *}"
        effective="${out#* }"
        case "$http_code" in [0-9][0-9][0-9]) ;; *) http_code="000" ;; esac
        verdict="$(classify_fetch "$curl_exit" "$http_code" "$(url_host "$url")")"
        if [ "$verdict" = "ok" ] && [ ! -s "$tmp" ]; then
            verdict="transient"      # a 200 with an empty body is a truncated response
        fi
        case "$verdict" in
            ok)
                if ! host_allowed "$effective"; then
                    rm -f "$tmp" "$hdr" "$err"
                    HTTP_GET_DETAIL="redirected to a host outside the allowlist: $effective"
                    return "$HTTP_BAD_HOST"
                fi
                mv -f "$tmp" "$dest"
                rm -f "$hdr" "$err"
                HTTP_GET_DETAIL="$(wc -c < "$dest" | tr -d ' ') bytes"
                return "$HTTP_OK" ;;
            permanent|rate-limited)
                HTTP_GET_DETAIL="$verdict (HTTP $http_code, curl exit $curl_exit): $(head -1 "$err" 2>/dev/null)"
                rm -f "$tmp" "$hdr" "$err"
                [ "$verdict" = "permanent" ] && return "$HTTP_PERMANENT"
                return "$HTTP_RATE_LIMITED" ;;
        esac
        if [ "$attempt" -ge "$RETRY_ATTEMPTS" ]; then
            HTTP_GET_DETAIL="transient (HTTP $http_code, curl exit $curl_exit) after $attempt attempts: $(head -1 "$err" 2>/dev/null)"
            rm -f "$tmp" "$hdr" "$err"
            return "$HTTP_TRANSIENT"
        fi
        asked="$(retry_after_secs "$hdr")"
        if [ -n "$asked" ]; then
            wait_secs="$asked"
        else
            wait_secs=$(( delay + RANDOM % (delay / 5 + 1) ))      # +0..20% jitter
        fi
        if [ "$wait_secs" -ge "$(deadline_remaining)" ]; then
            # Sleeping past the deadline would push the run toward the Bash tool's own
            # timeout, and a killed process prints no per-source table (ACCOUNT duty).
            HTTP_GET_DETAIL="transient (HTTP $http_code, curl exit $curl_exit) after $attempt attempts; the next retry (${wait_secs}s away) would overrun the ${DEADLINE_SECS}s deadline"
            rm -f "$tmp" "$hdr" "$err"
            return "$HTTP_TRANSIENT"
        fi
        warn "$url attempt $attempt/$RETRY_ATTEMPTS failed (HTTP $http_code, curl exit $curl_exit), retrying in ${wait_secs}s"
        sleep "$wait_secs"
        attempt=$(( attempt + 1 ))
        delay=$(( delay * 2 )); [ "$delay" -gt "$RETRY_CAP_SECS" ] && delay="$RETRY_CAP_SECS"
    done
}

# ------------------------------------------------------------ per-source ledger
# ACCOUNT duty: every source is attempted, recorded, and reconciled; the exit code
# comes from the reconciliation, never from the last command that happened to run.
TABLE=""
OK_COUNT=0; CACHED_COUNT=0; FAIL_COUNT=0; SKIPPED_COUNT=0; PARSE_ERROR_COUNT=0
record() {
    # record <source> <core|extended> <result> [<detail>]
    TABLE="${TABLE}$1 | $2 | $3 | ${4:-}
"
    case "$3" in
        ok*)     OK_COUNT=$(( OK_COUNT + 1 )) ;;
        cached)  CACHED_COUNT=$(( CACHED_COUNT + 1 )) ;;
        SKIPPED) SKIPPED_COUNT=$(( SKIPPED_COUNT + 1 )) ;;
        *)       FAIL_COUNT=$(( FAIL_COUNT + 1 )) ;;
    esac
}
print_table() {
    emit "source | class | result | detail"
    printf '%s' "$TABLE"
    emit "summary: $OK_COUNT ok, $CACHED_COUNT cached, $FAIL_COUNT failed or degraded, $SKIPPED_COUNT skipped"
}

fetch_simple() {
    # fetch_simple <source> <class> <url> <dest>
    if http_get "$3" "$4"; then
        record "$1" "$2" "ok" "$HTTP_GET_DETAIL"
        return 0
    fi
    record "$1" "$2" "FAILED" "$HTTP_GET_DETAIL"
    return 1
}

changelog_max_version() {
    # Newest version in a changelog file, whatever order the file lists them in.
    slice_changelog "$1" "0.0.0" "" 0 2>/dev/null | awk '
        function vnum(v,  part) { split(v, part, "."); return part[1] * 100000000 + part[2] * 10000 + part[3] }
        /^## / { if (vnum($2) > best) { best = vnum($2); name = $2 } }
        END { if (name != "") print name }'
}

version_lt() {
    awk -v a="$1" -v b="$2" '
        function vnum(v,  part) { split(v, part, "."); return part[1] * 100000000 + part[2] * 10000 + part[3] }
        BEGIN { exit !(vnum(a) < vnum(b)) }'
}

fetch_changelog() {
    # docs mirror (dated) -> GitHub raw -> the CLI's local cache. A source that
    # downloads but does not PARSE counts as failed too: partial format drift must
    # fall through, not masquerade as an empty week.
    local dest="$CACHE_DIR/$CHANGELOG_FILE_NAME" candidate="$CACHE_DIR/changelog.candidate" name url newest notes="" drifted=0
    for name in docs mirror; do
        url="$URL_CHANGELOG"; [ "$name" = "mirror" ] && url="$URL_CHANGELOG_MIRROR"
        if http_get "$url" "$candidate"; then
            newest="$(changelog_max_version "$candidate")"
            if [ -n "$newest" ]; then
                mv -f "$candidate" "$dest"
                record "changelog" "core" "ok ($name)" "newest $newest; $HTTP_GET_DETAIL$notes"
                return 0
            fi
            rm -f "$candidate"
            warn "changelog from $name downloaded but no version heading parsed (format drift?) — trying the next source"
            notes="$notes; $name did not parse"
            drifted=1
        else
            notes="$notes; $name: $HTTP_GET_DETAIL"
        fi
    done
    # No live source was usable. If one of them downloaded but did not parse, the run is
    # a PARSE error (exit 3): someone has to fix the parser, not wait for the network.
    [ "$drifted" -eq 1 ] && PARSE_ERROR_COUNT=$(( PARSE_ERROR_COUNT + 1 ))
    newest=""
    [ -s "$LOCAL_CHANGELOG" ] && newest="$(changelog_max_version "$LOCAL_CHANGELOG")"
    if [ -n "$newest" ]; then
        cp "$LOCAL_CHANGELOG" "$dest"
        record "changelog" "core" "STALE" "local CLI cache only, newest $newest — coverage must not advance past it$notes"
        return 1
    fi
    record "changelog" "core" "FAILED" "no changelog source usable$notes"
    return 1
}

fetch_digests() {
    local index="$CACHE_DIR/$INDEX_FILE_NAME" slug position=0 dest
    [ -s "$index" ] || { record "digests" "core" "FAILED" "no index in the cache to list them from"; return 1; }
    for slug in $(parse_index "$index" | awk -F'|' '{ print $1 }'); do
        position=$(( position + 1 ))
        # A slug becomes part of a filename and a URL, so its shape is checked first.
        case "$slug" in
            [0-9][0-9][0-9][0-9]-w[0-9]|[0-9][0-9][0-9][0-9]-w[0-9][0-9]) ;;
            *) record "digest $slug" "core" "FAILED" "malformed slug refused"; continue ;;
        esac
        dest="$CACHE_DIR/$DIGEST_DIR_NAME/$slug.md"
        if [ -s "$dest" ] && [ "$position" -gt "$ALWAYS_REFETCH_NEWEST_DIGESTS" ]; then
            record "digest $slug" "core" "cached" ""
            continue
        fi
        fetch_simple "digest $slug" "core" "$URL_DIGEST_BASE/$slug.md" "$dest"
    done
}

check_changelog_canary() {
    # A changelog that parses but trails the newest published CLI is how PARTIAL
    # format drift looks (old entries still parse, new ones are invisible).
    local changelog="$CACHE_DIR/$CHANGELOG_FILE_NAME" npm="$CACHE_DIR/npm-latest.json" newest latest
    if [ ! -s "$changelog" ] || [ ! -s "$npm" ]; then
        record "changelog-canary" "extended" "SKIPPED" "needs both the changelog and npm latest (each is recorded on its own row)"
        return 1
    fi
    newest="$(changelog_max_version "$changelog")"
    latest="$(json_path "$npm" version 2>/dev/null | head -1)"
    if ! is_version "${latest:-}"; then
        record "changelog-canary" "extended" "SKIPPED" "npm latest did not yield a version"
        return 1
    fi
    if version_lt "$newest" "$latest"; then
        record "changelog-canary" "core" "DEGRADED" "changelog newest $newest trails npm latest $latest — stale source or partial format drift"
        return 1
    fi
    record "changelog-canary" "core" "ok" "changelog newest $newest >= npm latest $latest"
}

cmd_fetch() {
    local index="$CACHE_DIR/$INDEX_FILE_NAME" index_candidate="$CACHE_DIR/whats-new.candidate" html="$CACHE_DIR/support-release-notes.html"
    mkdir -p "$CACHE_DIR/$DIGEST_DIR_NAME"
    trap 'record "interrupted" "core" "FAILED" "signal received before completion"; print_table; exit "$EXIT_PARTIAL"' TERM INT

    if http_get "$URL_INDEX" "$index_candidate"; then
        if [ -n "$(parse_index "$index_candidate")" ]; then
            mv -f "$index_candidate" "$index"
            record "whats-new-index" "core" "ok" "$HTTP_GET_DETAIL"
        else
            rm -f "$index_candidate"
            PARSE_ERROR_COUNT=$(( PARSE_ERROR_COUNT + 1 ))
            record "whats-new-index" "core" "FAILED" "parse error: downloaded but no weekly digest parsed — the page format drifted"
        fi
    else
        record "whats-new-index" "core" "FAILED" "$HTTP_GET_DETAIL"
    fi
    fetch_digests
    fetch_changelog
    fetch_simple "docs-index"     "extended" "$URL_DOCS_INDEX"     "$CACHE_DIR/llms.txt"
    fetch_simple "best-practices" "extended" "$URL_BEST_PRACTICES" "$CACHE_DIR/best-practices.md"
    fetch_simple "marketplace"    "extended" "$URL_MARKETPLACE"    "$CACHE_DIR/marketplace.json"
    fetch_simple "npm-latest"     "extended" "$URL_NPM_LATEST"     "$CACHE_DIR/npm-latest.json"
    if fetch_simple "support-notes" "extended" "$URL_SUPPORT_NOTES" "$html"; then
        render_html_text "$html" "$CACHE_DIR/support-release-notes.txt" \
            || record "support-notes-text" "extended" "FAILED" "could not render the HTML to text"
    fi
    check_changelog_canary

    trap - TERM INT
    print_table
    [ "$PARSE_ERROR_COUNT" -eq 0 ] || return "$EXIT_PARSE"
    [ "$FAIL_COUNT" -eq 0 ] || return "$EXIT_PARTIAL"
    [ "$SKIPPED_COUNT" -eq 0 ] || return "$EXIT_PARTIAL"
    return 0
}

# ----------------------------------------------------------------- watched pages
# Pages whose CONTENT changing is itself the news: the docs index (a new page is a
# new feature surface), the best-practices page, and the official plugin list.
# watch-diff is read-only; watch-commit promotes the pending snapshots, and the
# skill calls it only after the ledger is written — so a sweep that dies in
# between re-reports the same diff next time instead of losing it.

normalize_page() {
    # normalize_page <page> <out-file> -> the comparable form of a watched page; non-zero if unusable
    case "$1" in
        docs-index)     grep '^- \[' "$CACHE_DIR/llms.txt" | tr -d '\r' > "$2" ;;
        best-practices) tr -d '\r' < "$CACHE_DIR/best-practices.md" > "$2" ;;
        # Names only: a line diff of the manifest would churn on every version bump.
        marketplace)    json_path "$CACHE_DIR/marketplace.json" 'plugins[].name' 2>/dev/null | LC_ALL=C sort -u > "$2" ;;
    esac
    [ -s "$2" ]
}

page_source() {
    case "$1" in
        docs-index)     emit "$CACHE_DIR/llms.txt" ;;
        best-practices) emit "$CACHE_DIR/best-practices.md" ;;
        marketplace)    emit "$CACHE_DIR/marketplace.json" ;;
    esac
}

page_floor() {
    case "$1" in
        docs-index)     emit "$FLOOR_DOCS_INDEX" ;;
        best-practices) emit "$FLOOR_BEST_PRACTICES" ;;
        marketplace)    emit "$FLOOR_MARKETPLACE" ;;
    esac
}

cmd_watch_diff() {
    local snapshots="$LEDGER_DIR/$SNAPSHOT_DIR_NAME" page source current snapshot pending lines old_lines floor problems=0 added removed
    mkdir -p "$snapshots"
    for page in $WATCHED_PAGES; do
        source="$(page_source "$page")"
        snapshot="$snapshots/$page.txt"; pending="$snapshots/$page.pending"; current="$snapshots/$page.current.$$"
        if [ ! -s "$source" ]; then
            emit "$page: SKIPPED — not in the cache (run fetch; if fetch failed, this page's coverage must not advance)"
            problems=$(( problems + 1 )); continue
        fi
        if ! normalize_page "$page" "$current"; then
            rm -f "$current"
            emit "$page: REFUSED — the cached copy has no usable content (not the expected format)"
            problems=$(( problems + 1 )); continue
        fi
        lines="$(wc -l < "$current" | tr -d ' ')"; floor="$(page_floor "$page")"
        if [ "$lines" -lt "$floor" ]; then
            rm -f "$current"
            emit "$page: REFUSED — $lines entries is below the sanity floor of $floor (an error page, not an update)"
            problems=$(( problems + 1 )); continue
        fi
        if [ ! -f "$snapshot" ]; then
            mv -f "$current" "$pending"
            emit "$page: baseline ($lines entries) — no earlier snapshot, so changes before today are not diffed"
            continue
        fi
        old_lines="$(wc -l < "$snapshot" | tr -d ' ')"
        if [ "$old_lines" -gt 0 ] && [ $(( lines * 100 )) -lt $(( old_lines * (100 - MAX_SHRINK_PERCENT) )) ]; then
            rm -f "$current"
            emit "$page: REFUSED — shrank from $old_lines to $lines entries (more than ${MAX_SHRINK_PERCENT}%); treating it as a broken fetch"
            problems=$(( problems + 1 )); continue
        fi
        if cmp -s "$snapshot" "$current"; then
            rm -f "$current" "$pending"
            emit "$page: unchanged"
            continue
        fi
        local changes hidden
        changes="$(diff "$snapshot" "$current" | awk '/^>/ { sub(/^> ?/, "+ "); print } /^</ { sub(/^< ?/, "- "); print }')"
        added="$(printf '%s\n' "$changes" | grep -c '^+ ')"; removed="$(printf '%s\n' "$changes" | grep -c '^- ')"
        emit "$page: $added added, $removed removed"
        printf '%s\n' "$changes" | awk -v max="$WATCH_DIFF_MAX_LINES" 'NR <= max'
        hidden=$(( added + removed - WATCH_DIFF_MAX_LINES ))
        mv -f "$current" "$pending"
        [ "$hidden" -le 0 ] || emit "$page: … $hidden more changed line(s) not shown — the full new page is $pending"
    done
    [ "$problems" -eq 0 ] || return "$EXIT_PARTIAL"
    return 0
}

cmd_watch_commit() {
    # watch-commit [<name>...] — with no name, every pending snapshot; with names, only those.
    # A catch-up promotes only its own launches-seen: a bare commit would also promote page
    # diffs that a crashed sweep left pending and never wrote to the ledger.
    local snapshots="$LEDGER_DIR/$SNAPSHOT_DIR_NAME" pending name committed=0
    for name in "$@"; do
        # Only the snapshots this helper keeps: a mistyped name must never read as "nothing pending".
        case " $WATCHED_PAGES $LAUNCHES_SEEN_NAME " in
            *" $name "*) ;;
            *) die "$EXIT_USAGE" "watch-commit: '$name' is not a snapshot this helper keeps (one of: $WATCHED_PAGES $LAUNCHES_SEEN_NAME)" ;;
        esac
    done
    if [ $# -eq 0 ]; then
        set -- "$snapshots"/*.pending
    else
        for name in "$@"; do shift; set -- "$@" "$snapshots/$name.pending"; done
    fi
    for pending in "$@"; do
        [ -f "$pending" ] || continue
        mv -f "$pending" "${pending%.pending}.txt"
        emit "committed snapshot: $(basename "${pending%.pending}")"
        committed=$(( committed + 1 ))
    done
    [ "$committed" -gt 0 ] || emit "nothing pending"
    return 0
}

# ---------------------------------------------------------------------- launches
# The new-capability lens judges every LAUNCH (a new product, surface, extension point or
# way of working) for what it could do for the whole Claude Code system, not only as a
# tweak to a file that already exists. `launches` lists them deterministically from what
# fetch already cached (digest features, support-notes entries, new docs-index pages), so
# the lens can account for every one.
# - A weekly listing covers the last LAUNCH_LOOKBACK_DAYS; older launches are reached only
#   by a dated catch-up window (--since/--until). Dated launches therefore need no baseline:
#   a record adds exactly its own slice's keys, so a lane that failed is listed again.
# - Docs pages are undated. A machine's first record writes them as the baseline, and
#   --rebaseline-docs does it again, on purpose, after the docs index is reorganized.
# - Listing is read-only. --record writes .pending only after the result validates as
#   complete for that slice and every proposal's quote verifies against its own launch row;
#   watch-commit makes it final once the ledger is written.

launch_knob() {
    # launch_knob <variable> <value> — a tunable must be a plain whole number: a typo would
    # otherwise reach python as a traceback, or open a window that ends before it starts.
    case "$2" in
        ''|*[!0-9]*) die "$EXIT_USAGE" "$1 must be a whole number of at most 6 digits (got '$2')" ;;
    esac
    [ "${#2}" -le 6 ] || die "$EXIT_USAGE" "$1 must be a whole number of at most 6 digits (got '$2')"
}

cmd_launches() {
    local since="" until="" slice="" result="" mode="list"
    while [ $# -gt 0 ]; do
        case "$1" in
            --since)  { [ $# -ge 2 ] && [ -n "$2" ]; } || die "$EXIT_USAGE" "--since needs a date (YYYY-MM-DD)"
                      since="$2"; shift 2 ;;
            --until)  { [ $# -ge 2 ] && [ -n "$2" ]; } || die "$EXIT_USAGE" "--until needs a date (YYYY-MM-DD)"
                      until="$2"; shift 2 ;;
            --record) { [ $# -ge 3 ] && [ -n "$2" ] && [ -n "$3" ]; } || die "$EXIT_USAGE" "--record needs <slice> <result.json>"
                      mode="record"; slice="$2"; result="$3"; shift 3 ;;
            --rebaseline-docs) mode="rebaseline-docs"; shift ;;
            *)        die "$EXIT_USAGE" "launches: unknown argument '$1' (try --help)" ;;
        esac
    done
    launch_knob NEW_FUNCTIONALITY_CHECK_LAUNCH_LOOKBACK_DAYS "$LAUNCH_LOOKBACK_DAYS"
    launch_knob NEW_FUNCTIONALITY_CHECK_LAUNCH_SLICE_MAX "$LAUNCH_SLICE_MAX"
    if [ "$mode" != list ]; then
        [ -z "$since$until" ] || die "$EXIT_USAGE" "--$mode takes no window: it works on the seen-set as a whole"
    elif [ -n "$until" ] && [ -z "$since" ]; then
        die "$EXIT_USAGE" "--until needs --since"
    fi
    if [ "$mode" = record ]; then
        [ -f "$slice" ] || die "$EXIT_USAGE" "launches slice not found: $slice"
        [ -f "$result" ] || die "$EXIT_USAGE" "lens result not found: $result"
        # A slice listed with format drift came from a parser that was not trustworthy that day.
        if grep -q '^# FORMAT DRIFT:' "$slice"; then
            die "$EXIT_PARSE" "$slice was listed with format drift: fix the source, list again and judge that slice — nothing recorded"
        fi
        # Only a complete, verified result for THIS slice is recorded: a failed lane must come back.
        ( cmd_validate_candidates evaluator "$result" --launches "$slice" ) >/dev/null \
            || die "$EXIT_USAGE" "$result is not a valid, complete lens result for $slice — nothing recorded"
        ( quote_verifier batch "$result" "$slice" ) >/dev/null \
            || die "$EXIT_USAGE" "a proposal's quote in $result does not verify against its own launch row in $slice — re-dispatch; nothing recorded"
    fi
    [ "$mode" = list ] || mkdir -p "$LEDGER_DIR/$SNAPSHOT_DIR_NAME"
    find_python || die "$EXIT_USAGE" "launches needs a working python (none found)"
    LAUNCHES_MODE="$mode" LAUNCHES_CACHE="$CACHE_DIR" LAUNCHES_SNAPSHOTS="$LEDGER_DIR/$SNAPSHOT_DIR_NAME" \
    LAUNCHES_SEEN_NAME="$LAUNCHES_SEEN_NAME" LAUNCHES_TODAY="$(today_utc)" LAUNCHES_SINCE="$since" LAUNCHES_UNTIL="$until" \
    LAUNCHES_LOOKBACK_DAYS="$LAUNCH_LOOKBACK_DAYS" LAUNCHES_SLICE_MAX="$LAUNCH_SLICE_MAX" LAUNCHES_SLICE="$slice" \
    LAUNCHES_ALLOWED_HOSTS="$ALLOWED_HOSTS" LAUNCHES_OFFICIAL_URL="$OFFICIAL_URL_PATTERN" LAUNCHES_MARKER="$LAUNCHES_SLICE_MARKER" \
    LAUNCHES_URL_SUPPORT="$URL_SUPPORT_NOTES" LAUNCHES_URL_DIGEST_BASE="$URL_DIGEST_BASE" LAUNCHES_URL_DOCS_INDEX="$URL_DOCS_INDEX" \
        "$PYTHON_CMD" - <<'PY'
import datetime, hashlib, html, os, re, sys
from dataclasses import dataclass
from html.parser import HTMLParser
from urllib.parse import urljoin

def setting(name):
    return os.environ["LAUNCHES_" + name]

MODE, CACHE, SNAPSHOTS, SEEN_NAME = setting("MODE"), setting("CACHE"), setting("SNAPSHOTS"), setting("SEEN_NAME")
SINCE_TEXT, UNTIL_TEXT, SLICE_PATH, MARKER = setting("SINCE"), setting("UNTIL"), setting("SLICE"), setting("MARKER")
LOOKBACK_DAYS, SLICE_MAX = int(setting("LOOKBACK_DAYS")), int(setting("SLICE_MAX"))
ALLOWED, OFFICIAL_URL = set(setting("ALLOWED_HOSTS").split()), re.compile(setting("OFFICIAL_URL"))
URL_SUPPORT, URL_DIGEST_BASE, URL_DOCS_INDEX = setting("URL_SUPPORT"), setting("URL_DIGEST_BASE"), setting("URL_DOCS_INDEX")
EXIT_USAGE, EXIT_PARTIAL, EXIT_PARSE = 1, 2, 3
DOCS_EXCLUDED = ("/whats-new/", "/whats-new.md", "/changelog")   # digests and the changelog have their own lanes
TEXT_CAP = 2000     # characters of an entry's text the slice keeps
ECHO_CAP = 80       # characters of an unexpected heading or argument a message repeats
SEEN_PATH = os.path.join(SNAPSHOTS, SEEN_NAME + ".txt")
PENDING_PATH = os.path.join(SNAPSHOTS, SEEN_NAME + ".pending")

def die(code, message):
    print("claude-code-new-functionality-check: ERROR %s" % message, file=sys.stderr)
    sys.exit(code)

if not hasattr(datetime.date, "fromisocalendar"):
    die(EXIT_USAGE, "launches needs python 3.8 or later")

def day(text, flag):
    try:
        return datetime.datetime.strptime(text, "%Y-%m-%d").date()
    except ValueError:
        die(EXIT_USAGE, "%s must be a real date, YYYY-MM-DD (got %r)" % (flag, text[:ECHO_CAP]))

def norm(text):
    return re.sub(r"\s+", " ", text or "").strip()

def plain(fragment):
    return norm(html.unescape(re.sub(r"<[^>]+>", "", fragment or "")))

def key_part(text):
    return norm(text).lower().replace("|", "/")

def official(url):
    match = OFFICIAL_URL.match(url or "")
    return bool(match) and match.group(1) in ALLOWED

def capped(text):
    return text if len(text) <= TEXT_CAP else text[:TEXT_CAP].rstrip() + " …"

TODAY = day(setting("TODAY"), "today")

@dataclass
class Launch:
    source: str          # digest | support | docs
    date: object         # a datetime.date; None for a docs page, which is undated
    title: str
    text: str
    url: str             # the official page the launch was read from
    label: str           # how a slice row names the source
    key: str             # the launch's identity in the seen-set
    docs_url: str = ""   # the launch's own link, offered only when it is on an official host
    pill: str = ""
    note: str = ""

class Listing:
    """Every launch the cached sources hold, and what was missing or did not parse."""
    def __init__(self):
        self.launches, self.problems, self.skipped = [], [], []

def digest_launches(listing):
    folder = os.path.join(CACHE, "digests")
    names = sorted(name for name in os.listdir(folder) if re.match(r"^\d{4}-w\d{1,2}\.md$", name)) if os.path.isdir(folder) else []
    if not names:
        listing.skipped.append("digests — none in the cache (run fetch)")
        return
    for name in names:
        slug = name[:-3]
        year, week = slug.split("-w")
        try:
            monday = datetime.date.fromisocalendar(int(year), int(week), 1)
        except ValueError:
            listing.problems.append("digest %s is not a real ISO week" % slug)
            continue
        with open(os.path.join(folder, name), encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        blocks = re.split(r'<div className="digest-feature">', text)[1:]
        meta = re.search(r'className="digest-meta">(.*?)</div>', text, re.S)
        count = re.search(r"(\d+)\s+features?\b", meta.group(1)) if meta else None
        if count is None or int(count.group(1)) != len(blocks):
            listing.problems.append("digest %s: %d feature block(s), but its own count says %s (format drift)"
                                    % (slug, len(blocks), count.group(1) if count else "nothing"))
            continue
        for block in blocks:
            title = re.search(r'className="digest-feature-title">(.*?)</span>', block, re.S)
            lede = re.search(r'className="digest-feature-lede">(.*?)</p>', block, re.S)
            if not title or not lede or not plain(lede.group(1)):
                listing.problems.append("digest %s: a feature without a title or a lede (format drift)" % slug)
                continue
            pills = [plain(pill) for pill in re.findall(r'className="digest-feature-pill">(.*?)</span>', block, re.S)]
            link_tag = re.search(r'<a\b[^>]*className="digest-feature-link"[^>]*>', block)
            href = re.search(r'href="([^"]*)"', link_tag.group(0)) if link_tag else None
            docs_url = urljoin(URL_DIGEST_BASE + "/", href.group(1)) if href else ""
            listing.launches.append(Launch(
                "digest", monday, plain(title.group(1)), capped(plain(lede.group(1))), "%s/%s" % (URL_DIGEST_BASE, slug),
                "whats-new " + slug, "digest|%s|%s" % (slug, key_part(plain(title.group(1)))),
                docs_url if official(docs_url) else "", ", ".join(pill for pill in pills if pill)))

class NotesParser(HTMLParser):
    """The support notes as blocks: <h2> months, <h3> dates, and paragraph or list text. A <p>
    inside a list item belongs to that item: only a top-level paragraph can be an entry's title,
    one that is bold up to its end or up to a line break. Script and style text is never read."""
    HIDDEN = ("script", "style", "noscript")
    def __init__(self):
        HTMLParser.__init__(self, convert_charrefs=True)
        self.blocks, self.current, self.list_depth, self.hidden = [], None, 0, 0
    def open_block(self, tag):
        self.end_block()
        self.current = {"tag": tag, "before": [], "after": [], "bold": [], "in_bold": 0, "broken": False, "links": []}
    def end_block(self):
        if self.current is not None:
            self.blocks.append(self.current)
            self.current = None
    def handle_starttag(self, tag, attrs):
        if tag in self.HIDDEN:
            self.hidden += 1
            return
        if tag == "li":
            if self.list_depth == 0:
                self.open_block("li")
            self.list_depth += 1
            return
        if tag in ("h2", "h3") or (tag == "p" and self.list_depth == 0):
            self.open_block(tag)
            return
        block = self.current
        if block is None:
            return
        if tag in ("b", "strong"):
            block["in_bold"] += 1
        elif tag == "br":
            block["broken"] = True
        elif tag == "a":
            href = dict(attrs).get("href")
            if href:
                block["links"].append(href)
    def handle_endtag(self, tag):
        if tag in self.HIDDEN:
            self.hidden = max(0, self.hidden - 1)
            return
        block = self.current
        if tag == "li":
            self.list_depth = max(0, self.list_depth - 1)
            if self.list_depth == 0 and block is not None and block["tag"] == "li":
                self.end_block()
            return
        if block is None:
            return
        if tag in ("b", "strong") and block["in_bold"]:
            block["in_bold"] -= 1
        elif tag == block["tag"]:
            self.end_block()
    def handle_data(self, data):
        block = self.current
        if block is None or self.hidden:
            return
        (block["after"] if block["broken"] else block["before"]).append(data)
        if block["in_bold"] and not block["broken"]:
            block["bold"].append(data)

def support_launches(listing):
    path = os.path.join(CACHE, "support-release-notes.html")
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        listing.skipped.append("support notes — not in the cache (run fetch)")
        return
    with open(path, encoding="utf-8", errors="replace") as handle:
        page = handle.read()
    start, end = page.find("<article"), page.find("</article>")
    if start >= 0 and end > start:
        page = page[start:end]                      # the page's own navigation and footer are not entries
    parser = NotesParser()
    parser.feed(page)
    parser.close()                                  # flushes text the parser was still holding back
    parser.end_block()
    entries, date, entry, dates_seen = [], None, None, 0
    for block in parser.blocks:
        before, after = norm("".join(block["before"])), norm("".join(block["after"]))
        if block["tag"] == "h2":
            date, entry = None, None
            continue
        if block["tag"] == "h3":
            dates_seen += 1
            entry = None
            try:
                date = datetime.datetime.strptime(before, "%B %d, %Y").date()
            except ValueError:
                listing.problems.append("support notes: the date heading %r is not a date (format drift)" % before[:ECHO_CAP])
                date = None
            continue
        if date is None or not (before or after):
            continue
        bold = norm("".join(block["bold"]))
        if block["tag"] == "p" and bold and bold == before:
            entry = {"date": date, "title": bold, "body": [after] if after else [], "links": list(block["links"]) if after else []}
            entries.append(entry)
        elif entry is None:
            listing.problems.append("support notes: text before the first title of %s (format drift)" % date.isoformat())
        else:
            entry["body"].append(norm(before + " " + after))
            entry["links"].extend(block["links"])
    if dates_seen == 0:
        listing.problems.append("support notes: no dated entry at all (format drift)")
    for entry in entries:
        text = norm(" ".join(entry["body"]))
        if not text:
            listing.problems.append("support notes: the entry %r of %s has no text (format drift)"
                                    % (entry["title"][:ECHO_CAP], entry["date"].isoformat()))
            continue
        links = [urljoin(URL_SUPPORT, link) for link in entry["links"]]
        listing.launches.append(Launch(
            "support", entry["date"], entry["title"], capped(text), URL_SUPPORT, "support-notes",
            "support|%s|%s" % (entry["date"].isoformat(), key_part(entry["title"])),
            next((link for link in links if official(link)), "")))

def docs_launches(listing):
    path = os.path.join(CACHE, "llms.txt")
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        listing.skipped.append("docs index — not in the cache (run fetch)")
        return
    entries, urls = 0, set()
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = re.match(r"^- \[([^\]]+)\]\((https://[^)\s]+)\)(?::\s*(.*))?$", line.strip())
            if not match:
                continue
            entries += 1
            title, url, description = match.group(1), match.group(2), match.group(3) or ""
            if url in urls or any(part in url for part in DOCS_EXCLUDED):
                continue
            urls.add(url)
            listing.launches.append(Launch("docs", None, norm(title), capped(norm(description)), URL_DOCS_INDEX,
                                           "docs-index (new page)", "docs|" + url, url if official(url) else ""))
    if entries == 0:
        listing.problems.append("docs index: no page entries (format drift)")

def read_cache():
    listing = Listing()
    digest_launches(listing)
    support_launches(listing)
    docs_launches(listing)
    # A stable sort: within one day the digest features come first, as the sources were read,
    # and the undated docs pages come last.
    listing.launches.sort(key=lambda launch: launch.date or datetime.date.max)
    return listing

def read_keys(path):
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8", errors="replace") as handle:
        return set(line.rstrip("\n") for line in handle if line.strip())

def known_keys():
    # Everything already judged, committed or still pending: records accumulate, never replace.
    return (read_keys(SEEN_PATH) or set()) | (read_keys(PENDING_PATH) or set())

def write_pending(keys):
    # Beside the target and renamed, so a crash mid-write can never truncate the seen-set.
    scratch = PENDING_PATH + ".tmp"
    with open(scratch, "w", encoding="utf-8") as handle:
        handle.write("".join(key + "\n" for key in sorted(keys)))
    os.replace(scratch, PENDING_PATH)

def record_slice():
    with open(SLICE_PATH, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    rows = re.findall(r"^L[0-9]+ \|", text, re.M)
    keys = re.findall(r"^    key: (.+)$", text, re.M)
    if len(keys) != len(rows):
        die(EXIT_USAGE, "%s has %d key line(s) for %d launch(es): it was edited after it was listed — nothing recorded"
                        % (SLICE_PATH, len(keys), len(rows)))
    known, baseline = known_keys(), set()
    # The one baseline: docs pages are undated, so a page that exists at a machine's first record
    # is not a launch. That record writes every current page; later pages are listed as new.
    if not any(key.startswith("docs|") for key in known):
        docs = Listing()
        docs_launches(docs)
        baseline = set(launch.key for launch in docs.launches)
    write_pending(known | set(keys) | baseline)
    print("recorded %d judged launch(es)%s in %s — `watch-commit %s` (or the sweep's watch-commit) makes it final"
          % (len(keys), (" and %d docs page(s) as the docs baseline" % len(baseline)) if baseline else "", PENDING_PATH, SEEN_NAME))

def rebaseline_docs():
    docs = Listing()
    docs_launches(docs)
    if docs.problems or docs.skipped:
        die(EXIT_PARTIAL, "the docs index did not parse (%s) — nothing rebaselined" % "; ".join(docs.problems + docs.skipped))
    keys = set(launch.key for launch in docs.launches)
    write_pending(known_keys() | keys)
    print("recorded %d docs page(s) as the docs baseline in %s — `watch-commit %s` makes it final" % (len(keys), PENDING_PATH, SEEN_NAME))

def mark_retitled(chosen, listing, known):
    # An unseen entry on a date (or in a week) that holds as many entries as before, one of the
    # old ones now gone, was most likely re-titled upstream. The evaluator is told what to do.
    current = [launch.key for launch in listing.launches]
    for launch in chosen:
        if launch.source == "docs":
            continue
        prefix = launch.key.rsplit("|", 1)[0] + "|"
        gone = sorted(key[len(prefix):] for key in known if key.startswith(prefix) and key not in current)
        if gone and sum(key.startswith(prefix) for key in current) == sum(key.startswith(prefix) for key in known):
            launch.note = "possibly re-titled (seen before as: %s)" % "; ".join(gone)

def select(listing):
    dated = [launch for launch in listing.launches if launch.date is not None]
    if SINCE_TEXT:
        since = day(SINCE_TEXT, "--since")
        until = day(UNTIL_TEXT, "--until") if UNTIL_TEXT else TODAY
        if until < since:
            die(EXIT_USAGE, "--until %s is before --since %s" % (until, since))
        chosen = [launch for launch in dated if since <= launch.date <= until]
        if len(chosen) > SLICE_MAX:
            die(EXIT_USAGE, "%d launches between %s and %s: split the window (at most %d per slice, "
                            "NEW_FUNCTIONALITY_CHECK_LAUNCH_SLICE_MAX)" % (len(chosen), since, until, SLICE_MAX))
        return chosen, "catch-up %s → %s (dated launches, whatever the seen-set says; docs pages are never in a window)" % (since, until)
    seen = read_keys(SEEN_PATH)
    known = seen or set()
    start = TODAY - datetime.timedelta(days=LOOKBACK_DAYS)
    docs_baselined = any(key.startswith("docs|") for key in known)
    chosen = [launch for launch in dated if start <= launch.date <= TODAY and launch.key not in known]
    if docs_baselined:
        chosen += [launch for launch in listing.launches if launch.date is None and launch.key not in known]
    if len(chosen) > SLICE_MAX:
        die(EXIT_PARSE, "%d unseen launches (more than %d, NEW_FUNCTIONALITY_CHECK_LAUNCH_SLICE_MAX): a source's keys or "
                        "format may have changed, or the docs index was reorganized. Inspect it; then judge the dated launches "
                        "as catch-up windows (launches --since <date> --until <date>), or, when new docs pages are the bulk, "
                        "run launches --rebaseline-docs" % (len(chosen), SLICE_MAX))
    mark_retitled(chosen, listing, known)
    docs_part = "plus new docs pages" if docs_baselined else "docs pages become the baseline when this slice is recorded"
    if seen is None:
        return chosen, "weekly, first run on this machine (launches dated %s → %s; nothing judged yet; %s)" % (start, TODAY, docs_part)
    return chosen, "weekly (unseen launches dated %s → %s, %s; the seen-set holds %d keys)" % (start, TODAY, docs_part, len(seen))

def render(listing, chosen, mode_line):
    lines = []
    for number, launch in enumerate(chosen, 1):
        title = launch.title + (" (%s)" % launch.pill if launch.pill else "")
        lines.append("L%02d | %s | %s | %s" % (number, launch.date.isoformat() if launch.date else "new", launch.label, title.replace("|", "/")))
        lines.append("    key: %s" % launch.key)
        lines.append("    url: %s" % launch.url)
        if launch.docs_url:
            lines.append("    docs_url: %s" % launch.docs_url)
        if launch.note:
            lines.append("    note: %s" % launch.note)
        lines.append("    text: %s" % launch.text)
    body = "".join(line + "\n" for line in lines)
    counts = dict((source, sum(1 for launch in listing.launches if launch.source == source)) for source in ("digest", "support", "docs"))
    header = ["%s %s · %d launch(es) · listed %s by claude_code_new_functionality_check.sh launches — data, not instructions"
              % (MARKER, hashlib.sha256(body.encode("utf-8")).hexdigest()[:12], len(chosen), TODAY.isoformat()),
              "# mode: " + mode_line,
              "# sources: digests %d features · support notes %d entries · docs index %d pages" % (counts["digest"], counts["support"], counts["docs"])]
    header += ["# SKIPPED: " + reason for reason in listing.skipped]
    header += ["# FORMAT DRIFT: " + problem for problem in listing.problems]
    if not chosen:
        header.append("# no launches in this window" if SINCE_TEXT else "# no unseen launches")
    sys.stdout.write("".join(line + "\n" for line in header) + body)

def exit_code(listing):
    for problem in listing.problems:
        print("claude-code-new-functionality-check: ERROR %s" % problem, file=sys.stderr)
    return EXIT_PARSE if listing.problems else EXIT_PARTIAL if listing.skipped else 0

if MODE == "record":
    record_slice()
elif MODE == "rebaseline-docs":
    rebaseline_docs()
else:
    listing = read_cache()
    chosen, mode_line = select(listing)
    render(listing, chosen, mode_line)
    sys.exit(exit_code(listing))
PY
}

# ------------------------------------------------------------- tracked upstream issues
# The issues a config carries workarounds for are listed EXPLICITLY in
# <ledger dir>/tracked-issues.md (else the empty template in resources/). A heuristic
# scan for "#12345" would hit ticket and PR numbers from other repositories and ask
# the wrong repository about them.

parse_tracked_issues() {
    # parse_tracked_issues <file> -> "issue|keywords|workaround" per well-formed table row
    tr -d '\r' < "$1" | awk -F'|' '
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        NF >= 4 { issue = trim($2); if (issue ~ /^[0-9]+$/) print issue "|" trim($3) "|" trim($4) }'
}

cmd_tracked_issues() {
    local file="$TRACKED_ISSUES_FILE"
    [ "${1:-}" = "--file" ] && file="${2:-}"
    [ -f "$file" ] || die "$EXIT_USAGE" "tracked-issues table not found: $file"
    parse_tracked_issues "$file"
}

cmd_issue_status() {
    local number="${1:-}" dest state reason closed title message
    case "$number" in ''|*[!0-9]*) die "$EXIT_USAGE" "issue-status needs an issue number (got: '${number}')" ;; esac
    dest="$CACHE_DIR/issues/$number.json"
    if ! http_get "$URL_ISSUE_API_BASE/$number" "$dest"; then
        printf 'claude-code-new-functionality-check: ERROR issue #%s could not be read: %s\n' "$number" "$HTTP_GET_DETAIL" >&2
        return "$EXIT_PARTIAL"
    fi
    state="$(json_path "$dest" state | head -1)"
    if [ -z "$state" ]; then
        message="$(json_path "$dest" message | head -1)"
        printf 'claude-code-new-functionality-check: ERROR the issue API answered without a state for #%s: %s\n' "$number" "${message:-unrecognized response}" >&2
        return "$EXIT_PARTIAL"
    fi
    reason="$(json_path "$dest" state_reason | head -1)"
    closed="$(json_path "$dest" closed_at | head -1)"
    title="$(json_path "$dest" title | head -1)"
    emit "#$number | $state | ${reason:--} | ${closed:--} | $title"
}

cmd_issue_evidence() {
    # Every changelog bullet — Fixed ones included — that mentions a tracked issue's
    # keywords. The backfill slices drop Fixed bullets, and a fix is exactly what
    # retires a workaround, so this lane reads the full file.
    local number="" tracked="$TRACKED_ISSUES_FILE" file="$CACHE_DIR/$CHANGELOG_FILE_NAME" keywords
    while [ $# -gt 0 ]; do
        case "$1" in
            --tracked) shift; tracked="${1:-}" ;;
            --file)    shift; file="${1:-}" ;;
            *)         number="$1" ;;
        esac
        shift
    done
    case "$number" in ''|*[!0-9]*) die "$EXIT_USAGE" "issue-evidence needs an issue number" ;; esac
    [ -f "$tracked" ] || die "$EXIT_USAGE" "tracked-issues table not found: $tracked"
    [ -f "$file" ] || die "$EXIT_USAGE" "changelog file not found: $file (run: claude_code_new_functionality_check.sh fetch)"
    keywords="$(parse_tracked_issues "$tracked" | awk -F'|' -v n="$number" '$1 == n { print $2; exit }')"
    [ -n "$keywords" ] || die "$EXIT_USAGE" "issue #$number is not in $tracked — add a row with its keywords first"
    slice_changelog "$file" "0.0.0" "" 0 | awk -v list="$keywords" -v number="$number" '
        BEGIN { count = split(tolower(list), words, /[ \t]*,[ \t]*/); words[count + 1] = "#" number; count++ }
        /^## / { heading = $0; printed = 0; next }
        {
            line = tolower($0)
            for (i = 1; i <= count; i++) {
                if (words[i] != "" && index(line, words[i]) > 0) {
                    if (!printed) { print heading; printed = 1 }
                    print
                    break
                }
            }
        }'
    return 0
}

# ------------------------------------------------------- deterministic verification
# An agent that read a web page may not be the one who says its claim is "verified".
# These two subcommands make verification a fact: the text is in a file the HELPER
# fetched from an official host, or it is not.

quote_verifier() {
    # quote_verifier single <file> <quote>   |   quote_verifier batch <results.json> <slice-file>...
    # ONE implementation behind verify-quote, verify-lead and verify-candidates, so the
    # verifiers cannot disagree. Every whitespace run — line breaks, tabs, form feeds, the
    # non-breaking spaces that rendered HTML is full of — equals one space on both sides;
    # every other character must match exactly, in order.
    find_python || die "$EXIT_USAGE" "quote verification needs a working python (none found)"
    LAUNCHES_MARKER="$LAUNCHES_SLICE_MARKER" "$PYTHON_CMD" - "$MIN_QUOTE_CHARS" "$@" <<'PY'
import json, os, re, sys
minimum, mode, arguments = int(sys.argv[1]), sys.argv[2], sys.argv[3:]
MARKER = os.environ.get("LAUNCHES_MARKER", "")

def normalize(text):
    return re.sub(r"\s+", " ", text).strip()

def read_normalized(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return normalize(handle.read())
    except OSError as problem:
        print("claude-code-new-functionality-check: ERROR cannot read %s: %s" % (path, problem), file=sys.stderr)
        sys.exit(1)

if mode == "single":
    path, quote = arguments[0], normalize(arguments[1])
    if len(quote) < minimum:
        print("claude-code-new-functionality-check: ERROR a quote under %d characters proves nothing (got %d)" % (minimum, len(quote)), file=sys.stderr)
        sys.exit(1)
    found = quote in read_normalized(path)
    print("%s: quote %s in %s" % ("verified" if found else "NOT verified", "found" if found else "not found", path))
    sys.exit(0 if found else 1)

results, haystacks = arguments[0], [read_normalized(path) for path in arguments[1:]]
with open(results, encoding="utf-8") as handle:
    document = json.load(handle)
header = document.get("header") if isinstance(document.get("header"), dict) else {}

def launch_texts(path):
    # {launch id: its row's text}. A lens proposal's quote must come from its OWN launch, never
    # from another row or from the slice's header lines.
    with open(path, encoding="utf-8", errors="replace") as handle:
        rows = re.split(r"(?m)^(?=L[0-9]+ \|)", handle.read())
    texts = {}
    for row in rows:
        ident, text = re.match(r"^(L[0-9]+) \|", row), re.search(r"^    text: (.*)$", row, re.M)
        if ident and text:
            texts[ident.group(1)] = normalize(text.group(1))
    return texts

rows = {}
for path, haystack in zip(arguments[1:], haystacks):
    if MARKER and haystack.startswith(MARKER):
        # A launches slice belongs to the new-capability lens: pairing it with any other result
        # means the lens's completeness check was skipped.
        if header.get("lens") != "new-capability":
            print("claude-code-new-functionality-check: ERROR %s is a launches slice: only a new-capability result "
                  "(header.lens) is verified against it" % path, file=sys.stderr)
            sys.exit(1)
        rows.update(launch_texts(path))
checked = verified = 0
for number, item in enumerate(document.get("candidates", []), 1):
    if item.get("verdict") == "NO-ACTION":
        continue
    checked += 1
    quote = normalize(str((item.get("upstream") or {}).get("quote", "")))
    launch = item.get("launch")
    pool = [rows.get(launch, "") if isinstance(launch, str) else ""] if rows else haystacks
    found = len(quote) >= minimum and any(quote in haystack for haystack in pool)
    verified += 1 if found else 0
    print("%s | %d | %s" % ("verified" if found else "NOT-VERIFIED", number, item.get("title", "")))
print("%d of %d actionable quotes verified" % (verified, checked))
sys.exit(0 if verified == checked else 1)
PY
}

cmd_verify_quote() {
    local file="${1:-}" quote="${2:-}"
    [ -f "$file" ] || { printf 'claude-code-new-functionality-check: ERROR source file not found: %s\n' "$file" >&2; return 1; }
    quote_verifier single "$file" "$quote"
}

cmd_verify_lead() {
    local url="${1:-}" quote="${2:-}" dest text fetched age
    case "$url" in
        https://*) host_allowed "$url" || { printf 'claude-code-new-functionality-check: NOT verified — %s is not an official host\n' "$(url_host "$url")" >&2; return 1; } ;;
        *)
            # Anything but https is only reachable in the offline fixtures.
            if [ "${NEW_FUNCTIONALITY_CHECK_VERIFY_ANY_HOST:-0}" != "1" ]; then
                printf 'claude-code-new-functionality-check: NOT verified — only https URLs on official hosts can verify a lead (got: %s)\n' "$url" >&2
                return 1
            fi ;;
    esac
    dest="$CACHE_DIR/leads/$(printf '%s' "$url" | cksum | tr -s ' \t' '--')"
    fetched="$(path_mtime_epoch "$dest")"
    case "$fetched" in ''|*[!0-9]*) fetched=0 ;; esac
    age=$(( $(date +%s) - fetched ))
    if [ -s "$dest" ] && [ "$age" -lt "$LEAD_CACHE_FRESH_SECS" ]; then
        emit "reusing the copy of $url fetched ${age}s ago"
    elif ! http_get "$url" "$dest"; then
        printf 'claude-code-new-functionality-check: ERROR could not fetch %s to verify it: %s\n' "$url" "$HTTP_GET_DETAIL" >&2
        return "$EXIT_PARTIAL"
    fi
    text="$dest"
    if grep -q -i -E '<html|<!doctype' "$dest"; then
        text="$dest.txt"
        render_html_text "$dest" "$text" || { printf 'claude-code-new-functionality-check: ERROR could not render %s\n' "$url" >&2; return "$EXIT_PARTIAL"; }
    fi
    cmd_verify_quote "$text" "$quote"
}

cmd_verify_candidates() {
    # verify-candidates <results.json> <slice-file>... — verify-quote for a whole result
    # file (NO-ACTION candidates are skipped: nothing actionable hangs on their quotes).
    local results="${1:-}"
    [ -f "$results" ] || die "$EXIT_USAGE" "results file not found: $results"
    shift
    [ $# -ge 1 ] || die "$EXIT_USAGE" "verify-candidates needs at least one slice file to check quotes against"
    quote_verifier batch "$results" "$@"
}

# ------------------------------------------------------------------ scrub-check
# Search queries and fetched URLs are the only things that leave this machine
# during a sweep, and the main session writes them from an inventory full of
# private names. The agenda is therefore checked against a per-machine denylist
# BEFORE a researcher is dispatched.

cmd_scrub_check() {
    local file="${1:-}" denylist="$LEDGER_DIR/denylist.txt" terms term listed hits=0
    [ -f "$file" ] || die "$EXIT_USAGE" "agenda file not found: $file"
    terms="$(printf '%s\n%s\n%s\n' "${NEW_FUNCTIONALITY_CHECK_SCRUB_USER:-${USER:-}}" "${NEW_FUNCTIONALITY_CHECK_SCRUB_HOME:-$HOME}" \
                 "${NEW_FUNCTIONALITY_CHECK_SCRUB_HOST:-$(hostname -s 2>/dev/null)}")"
    # Fail CLOSED: the three built-in terms cannot know a client or a colleague by
    # name, so without a seeded denylist a "clean" verdict would mean nothing — and the
    # agenda is the one thing that leaves this machine.
    if [ ! -f "$denylist" ]; then
        printf 'claude-code-new-functionality-check: BLOCKED no denylist at %s — seed it (one private term per line: client and engagement names, private repo names, people) before dispatching any research agenda\n' "$denylist" >&2
        return 1
    fi
    listed="$(tr -d '\r' < "$denylist" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$')"
    if [ -z "$listed" ]; then
        printf 'claude-code-new-functionality-check: BLOCKED the denylist at %s lists no terms — a pass against an empty list proves nothing\n' "$denylist" >&2
        return 1
    fi
    terms="$terms
$listed"
    while IFS= read -r term; do
        [ "${#term}" -ge "$MIN_SCRUB_TERM_CHARS" ] || continue
        if grep -n -i -F -- "$term" "$file" >/dev/null 2>&1; then
            grep -n -i -F -- "$term" "$file" | while IFS=: read -r line_no _; do
                printf 'claude-code-new-functionality-check: BLOCKED line %s contains a private term (%s)\n' "$line_no" "$term" >&2
            done
            hits=$(( hits + 1 ))
        fi
    done <<SCRUB_TERMS
$terms
SCRUB_TERMS
    if [ "$hits" -gt 0 ]; then
        printf 'claude-code-new-functionality-check: BLOCKED do not dispatch this agenda — rewrite it in public technical terms only\n' >&2
        return 1
    fi
    emit "scrub-check: clean"
    return 0
}

# ------------------------------------------------------------------ save-result
# A subagent's reply is never retyped. Its transcript holds the agent's own bytes;
# the notification text is a harness-escaped copy (< > & become entities when the
# output looks instruction-shaped), and a long reply is split when the agent hits
# its output-token limit: the harness injects a plain-string "Output token limit
# hit" prompt and the agent continues mid-word in the next message.
cmd_save_result() {
    local out="${1:-}" transcript="${2:-}"
    [ -n "$out" ] || die "$EXIT_USAGE" "save-result needs an output path: save-result <out.json> [<transcript.jsonl>]"
    if [ -n "$transcript" ] && [ ! -f "$transcript" ]; then
        die "$EXIT_USAGE" "transcript not found: $transcript"
    fi
    find_python || die "$EXIT_USAGE" "save-result needs a working python (none found)"
    # The program is passed with -c because stdin may be carrying the pasted reply.
    "$PYTHON_CMD" -c '
import html, json, os, sys
out_path, transcript = sys.argv[1], sys.argv[2]
CONTINUATION_PREFIX = "Output token limit hit"

def reply_from_transcript(path):
    """The reply an agent handed back through a SubagentHandback tool call (its input.message,
    the agent own bytes; the last one wins). Without one: every assistant text block after
    the last tool result, joined in order."""
    pieces = []
    handback = None
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            content = (entry.get("message") or {}).get("content")
            if entry.get("type") == "user":
                if isinstance(content, str):
                    if not content.startswith(CONTINUATION_PREFIX):
                        pieces = []
                elif isinstance(content, list) and any(part.get("type") == "tool_result" for part in content):
                    pieces = []
            elif entry.get("type") == "assistant" and isinstance(content, list):
                for part in content:
                    if part.get("type") == "tool_use" and part.get("name") == "SubagentHandback":
                        message = (part.get("input") or {}).get("message")
                        if isinstance(message, str) and message.strip():
                            handback = message
                text = "".join(part.get("text", "") for part in content if part.get("type") == "text")
                if text:
                    pieces.append(text)
    if handback is not None:
        return handback, 1
    return "".join(pieces), len(pieces)

if transcript:
    reply, piece_count = reply_from_transcript(transcript)
else:
    reply, piece_count = html.unescape(sys.stdin.read()), 1
start, end = reply.find("{"), reply.rfind("}")
if start < 0 or end <= start:
    sys.exit("claude-code-new-functionality-check: ERROR no JSON object in the reply (%d characters) — a failed lane, not an empty result" % len(reply))
try:
    document = json.loads(reply[start:end + 1])
except ValueError as problem:
    sys.exit("claude-code-new-functionality-check: ERROR the reply is not strict JSON: %s" % problem)
if not isinstance(document, dict):
    sys.exit("claude-code-new-functionality-check: ERROR the reply is JSON but not an object")
scratch = out_path + ".tmp"
with open(scratch, "w", encoding="utf-8") as handle:
    json.dump(document, handle, ensure_ascii=False, indent=1)
os.replace(scratch, out_path)
kind = "candidates" if "candidates" in document else "leads"
print("saved %s (%d %s; reply in %d piece(s))" % (out_path, len(document.get(kind, [])), kind, piece_count))
' "$out" "$transcript"
}

# ------------------------------------------------------------ validate-candidates
# Subagent output is DATA. Before any of it reaches the ledger it must be strict
# JSON with whitelisted fields, capped lengths, no control characters, and only
# official hosts where an official host is claimed. (Python is required here: a
# field whitelist with nested rules is not something to improvise in jq.)
cmd_validate_candidates() {
    # validate-candidates <evaluator|researcher> <file> [--launches <slice>]. Arguments are parsed
    # strictly: a mistyped flag must be an error, never a silently skipped completeness check.
    local kind="${1:-}" file="${2:-}" launches=""
    case "$kind" in evaluator|researcher) ;; *) die "$EXIT_USAGE" "validate-candidates needs a kind: evaluator | researcher" ;; esac
    if [ $# -ge 2 ]; then shift 2; else shift $#; fi
    while [ $# -gt 0 ]; do
        case "$1" in
            --launches)
                [ "$kind" = evaluator ] || die "$EXIT_USAGE" "--launches applies to evaluator results only"
                { [ $# -ge 2 ] && [ -n "$2" ]; } || die "$EXIT_USAGE" "--launches needs the slice file the result judged"
                launches="$2"; shift 2 ;;
            *) die "$EXIT_USAGE" "validate-candidates: unknown argument '$1'" ;;
        esac
    done
    [ -f "$file" ] || die "$EXIT_USAGE" "candidates file not found: $file"
    [ -z "$launches" ] || [ -f "$launches" ] || die "$EXIT_USAGE" "launches slice not found: $launches"
    find_python || die "$EXIT_USAGE" "validate-candidates needs a working python (none found)"
    "$PYTHON_CMD" - "$kind" "$file" "$ALLOWED_HOSTS" "$FIELD_CAPS_JSON" "$OVERLONG_FACTOR" "$launches" "$BREADTHS" \
        "$DISPOSITION_CLASSES" "$OFFICIAL_URL_PATTERN" <<'PY'
import hashlib, json, re, sys
kind, path, allowed_hosts = sys.argv[1], sys.argv[2], set(sys.argv[3].split())
CAPS, OVERLONG_FACTOR = json.loads(sys.argv[4]), int(sys.argv[5])
LAUNCHES, BREADTHS, CLASSES = sys.argv[6], set(sys.argv[7].split()), set(sys.argv[8].split())
OFFICIAL_URL = re.compile(sys.argv[9])
MIN_WHY = 8        # a disposition's reason must actually say something ("n/a" does not)
DEFAULT_CAP = 300
MAX_ITEMS = 40
VERDICTS = {"PROPOSE", "RISK-WATCH", "NO-ACTION"}
TARGETS = {"hook", "skill", "agent", "settings", "claude-md", "plugin", "work-practice", "other"}
TIERS = {"official-docs", "official-blog", "vendor", "community", "issue-tracker"}
LEVELS = {"benefit": {"H", "M", "L"}, "effort": {"trivial", "S", "M", "L", "XL"}, "risk": {"low", "med", "high"}}
CONTROL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
MIN_QUOTE = 20
errors = []
overlong = []

def fail(where, message):
    errors.append("%s: %s" % (where, message))

def check_string(where, key, value, required=False):
    if not isinstance(value, str):
        fail(where, "%s must be a string" % key); return
    if required and not value.strip():
        fail(where, "%s is required" % key)
    if CONTROL.search(value):
        fail(where, "%s contains a control character" % key)
    cap = CAPS.get(key, DEFAULT_CAP)
    if len(value) > cap * OVERLONG_FACTOR:
        fail(where, "%s is longer than %d characters (%d, more than %dx the cap)" % (key, cap, len(value), OVERLONG_FACTOR))
    elif len(value) > cap:
        overlong.append("%s: %s is %d characters (cap %d) — reword it while curating; never log it verbatim" % (where, key, len(value), cap))

def host_of(url):
    match = OFFICIAL_URL.match(url)
    return match.group(1) if match else None

def one_of(value, allowed):
    # Membership that cannot crash: a list or an object where a word belongs is just "not one of".
    return isinstance(value, str) and value in allowed

def check_url(where, key, value, official, required=False):
    check_string(where, key, value, required)
    if not isinstance(value, str) or not value:
        return
    host = host_of(value)
    if host is None:
        fail(where, "%s must be a clean https URL (no userinfo, whitespace or markup characters)" % key)
    elif official and host not in allowed_hosts:
        fail(where, "%s host %s is not an official host" % (key, host))

def only_keys(where, obj, allowed):
    if not isinstance(obj, dict):
        fail(where, "must be an object"); return False
    for key in obj:
        if key not in allowed:
            fail(where, "unknown field '%s'" % key)
    return True

def check_levels(where, item, required):
    for key, allowed in LEVELS.items():
        if key in item:
            if not one_of(item[key], allowed):
                fail(where, "%s must be one of %s" % (key, sorted(allowed)))
        elif required:
            fail(where, "%s is required" % key)

def check_common(where, item, required):
    check_string(where, "title", item.get("title", ""), True)
    check_string(where, "feature_key", item.get("feature_key", ""), True)
    if not one_of(item.get("target_type"), TARGETS):
        fail(where, "target_type must be one of %s" % sorted(TARGETS))
    check_levels(where, item, required)
    if required and not isinstance(item.get("sensitive"), bool):
        fail(where, "sensitive (true/false) is required")

def read_slice(slice_path):
    # (stated slice-id, slice-id of the content, launch ids) — the hash covers everything from the
    # first launch line on, so a slice edited after it was listed no longer matches its own id.
    with open(slice_path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    stated = re.search(r"slice-id ([0-9a-f]{12})", text)
    first = re.search(r"^L[0-9]+ \|", text, re.M)
    body = text[first.start():] if first else ""
    return (stated.group(1) if stated else None,
            hashlib.sha256(body.encode("utf-8")).hexdigest()[:12],
            re.findall(r"^(L[0-9]+) \|", text, re.M))

def check_lens(header, items):
    # The new-capability lens: every launch in the slice gets exactly one disposition, every
    # new capability exactly one PROPOSE, and nothing is omitted. Silence is never a result.
    stated, content, ids = read_slice(LAUNCHES)
    if stated is None:
        fail("launches", "%s is not a launches slice (it has no slice-id)" % LAUNCHES); return {}
    if stated != content:
        fail("launches", "the slice was edited after it was listed (slice-id %s, content %s)" % (stated, content))
    if header.get("lens") != "new-capability":
        fail("header", "lens must be \"new-capability\" in a launches result")
    if stated not in str(header.get("slice", "")):
        fail("header", "slice must name slice-id %s: this result was made for another slice" % stated)
    if header.get("items_reviewed") != len(ids):
        fail("header", "items_reviewed must be %d, the number of launches in the slice" % len(ids))
    if header.get("omitted_count") != 0:
        fail("header", "omitted_count must be 0: under the lens every launch gets a disposition")
    by_launch = {}
    dispositions = header.get("dispositions")
    if not isinstance(dispositions, list):
        fail("header", "dispositions must be a list, one entry per launch"); dispositions = []
    for number, entry in enumerate(dispositions, 1):
        where = "disposition %d" % number
        if not only_keys(where, entry, {"launch", "class", "why"}):
            continue
        launch = entry.get("launch")
        if not one_of(launch, ids):
            fail(where, "launch %r is not in the slice" % (launch,)); continue
        if launch in by_launch:
            fail(where, "%s has two dispositions" % launch); continue
        if not one_of(entry.get("class"), CLASSES):
            fail(where, "class must be one of %s" % sorted(CLASSES))
        why = entry.get("why", "")
        check_string(where, "why", why, True)
        if isinstance(why, str) and why.strip() and len(why.strip()) < MIN_WHY:
            fail(where, "why must give the reason in at least %d characters, not a stub" % MIN_WHY)
        by_launch[launch] = entry.get("class") if isinstance(entry.get("class"), str) else None
    missing = [launch for launch in ids if launch not in by_launch]
    if missing:
        fail("header", "no disposition for %s: every launch gets one" % ", ".join(missing))
    proposed = set()
    for number, item in enumerate(items[:MAX_ITEMS], 1):
        where = "candidate %d" % number
        if not isinstance(item, dict):
            continue
        if item.get("verdict") != "PROPOSE":
            fail(where, "under the lens only PROPOSE candidates exist; a launch with no fit says why in its disposition"); continue
        launch = item.get("launch")
        if not isinstance(launch, str) or by_launch.get(launch) != "new-capability":
            fail(where, "launch %r has no new-capability disposition" % (launch,)); continue
        if launch in proposed:
            fail(where, "%s has two proposals" % launch)
        proposed.add(launch)
        check_string(where, "capability", item.get("capability", ""), True)
        if not one_of(item.get("breadth"), BREADTHS):
            fail(where, "breadth must be one of %s" % sorted(BREADTHS))
    for launch in ids:
        if by_launch.get(launch) == "new-capability" and launch not in proposed:
            fail("header", "%s is judged a new capability but has no PROPOSE" % launch)
    return by_launch

def check_evaluator(doc):
    if not only_keys("document", doc, {"header", "candidates"}):
        return
    header = doc.get("header")
    header_keys = {"slice", "items_reviewed", "omitted_count"} | ({"lens", "dispositions"} if LAUNCHES else set())
    if isinstance(header, dict) and "lens" in header and not LAUNCHES:
        fail("header", "a lens result is validated with --launches <the slice it judged>")
    if only_keys("header", header, header_keys):
        check_string("header", "slice", header.get("slice", ""), True)
        for key in ("items_reviewed", "omitted_count"):
            if not isinstance(header.get(key), int) or isinstance(header.get(key), bool) or header.get(key) < 0:
                fail("header", "%s must be a non-negative integer (silent truncation is not allowed)" % key)
    items = doc.get("candidates")
    if not isinstance(items, list):
        fail("document", "candidates must be a list"); return
    if len(items) > MAX_ITEMS:
        fail("document", "more than %d candidates in one dispatch" % MAX_ITEMS)
    allowed = {"verdict", "title", "feature_key", "target_type", "target_paths", "upstream", "today", "proposed_change",
               "benefit", "effort", "risk", "sensitive", "verify_before_adopting", "reason_if_no_action"}
    if LAUNCHES:
        allowed |= {"launch", "capability", "breadth"}
    for number, item in enumerate(items[:MAX_ITEMS], 1):
        where = "candidate %d" % number
        if not only_keys(where, item, allowed):
            continue
        verdict = item.get("verdict")
        if not one_of(verdict, VERDICTS):
            fail(where, "verdict must be one of %s" % sorted(VERDICTS)); continue
        actionable = verdict != "NO-ACTION"
        check_common(where, item, actionable)
        for path_value in item.get("target_paths", []) if isinstance(item.get("target_paths", []), list) else [None]:
            check_string(where, "target_paths", path_value if path_value is not None else 0)
        upstream = item.get("upstream")
        if only_keys(where + ".upstream", upstream, {"source", "ref", "version", "url", "docs_url", "quote"}):
            check_url(where, "url", upstream.get("url", ""), True, True)
            if "docs_url" in upstream:
                check_url(where, "docs_url", upstream["docs_url"], True)
            for key in ("source", "ref", "version"):
                if key in upstream:
                    check_string(where, key, upstream[key])
            quote = upstream.get("quote", "")
            check_string(where, "quote", quote, True)
            if isinstance(quote, str) and len(quote.strip()) < MIN_QUOTE:
                fail(where, "quote must be a verbatim excerpt of at least %d characters" % MIN_QUOTE)
        for key in ("today", "proposed_change", "verify_before_adopting", "reason_if_no_action"):
            if key in item:
                check_string(where, key, item[key])
        if verdict == "PROPOSE" and not str(item.get("proposed_change", "")).strip():
            fail(where, "a PROPOSE needs a concrete proposed_change")
        if verdict == "NO-ACTION" and not str(item.get("reason_if_no_action", "")).strip():
            fail(where, "a NO-ACTION needs reason_if_no_action")
    counts = dict((v, sum(1 for i in items if isinstance(i, dict) and i.get("verdict") == v)) for v in VERDICTS)
    summary = "%d PROPOSE, %d RISK-WATCH, %d NO-ACTION" % (counts["PROPOSE"], counts["RISK-WATCH"], counts["NO-ACTION"])
    if LAUNCHES and isinstance(header, dict):
        judged = list(check_lens(header, items).values())
        summary += "; dispositions: %d new-capability, %d iteration, %d no-fit" % (
            judged.count("new-capability"), judged.count("iteration"), judged.count("no-fit"))
    return summary

def check_researcher(doc):
    if not only_keys("document", doc, {"header", "leads"}):
        return
    header = doc.get("header")
    if only_keys("header", header, {"lanes_completed", "budget_used", "fetch_failures"}):
        if not isinstance(header.get("lanes_completed"), list):
            fail("header", "lanes_completed must be a list")
        budget = header.get("budget_used")
        if only_keys("header.budget_used", budget, {"searches", "fetches"}):
            for key in ("searches", "fetches"):
                if not isinstance(budget.get(key), int) or isinstance(budget.get(key), bool):
                    fail("header", "budget_used.%s must be an integer" % key)
        failures = header.get("fetch_failures")
        if not isinstance(failures, list):
            fail("header", "fetch_failures must be a list (empty when none)")
        else:
            for failure in failures:
                if only_keys("header.fetch_failures", failure, {"url", "reason"}):
                    check_string("header.fetch_failures", "url", failure.get("url", ""))
                    check_string("header.fetch_failures", "reason", failure.get("reason", ""))
    items = doc.get("leads")
    if not isinstance(items, list):
        fail("document", "leads must be a list"); return
    if len(items) > MAX_ITEMS:
        fail("document", "more than %d leads in one dispatch" % MAX_ITEMS)
    allowed = {"title", "feature_key", "target_type", "source_tier", "url", "quote", "claim", "proposed_change",
               "benefit", "effort", "risk", "sensitive", "verification"}
    for number, item in enumerate(items[:MAX_ITEMS], 1):
        where = "lead %d" % number
        if not only_keys(where, item, allowed):
            continue
        check_common(where, item, True)
        if not one_of(item.get("source_tier"), TIERS):
            fail(where, "source_tier must be one of %s" % sorted(TIERS))
        check_url(where, "url", item.get("url", ""), False, True)
        quote = item.get("quote", "")
        check_string(where, "quote", quote, True)
        if isinstance(quote, str) and len(quote.strip()) < MIN_QUOTE:
            fail(where, "quote must be a verbatim excerpt of at least %d characters" % MIN_QUOTE)
        check_string(where, "claim", item.get("claim", ""), True)
        if "proposed_change" in item:
            check_string(where, "proposed_change", item["proposed_change"])
        verification = item.get("verification")
        if only_keys(where + ".verification", verification, {"status", "by_url", "by_quote"}):
            status = verification.get("status")
            if status not in ("verified", "unverified"):
                fail(where, "verification.status must be verified or unverified")
            if status == "verified":
                # The agent's word is not enough: the verifying page must at least be official.
                # (The helper's verify-lead then checks the quote itself.)
                check_url(where, "by_url", verification.get("by_url", ""), True, True)
                check_string(where, "by_quote", verification.get("by_quote", ""), True)
    return "%d leads (%d claimed verified)" % (len(items), sum(1 for i in items if isinstance(i, dict) and isinstance(i.get("verification"), dict) and i["verification"].get("status") == "verified"))

try:
    with open(path, encoding="utf-8") as handle:
        document = json.load(handle)
except ValueError as problem:
    print("claude-code-new-functionality-check: ERROR %s is not strict JSON: %s" % (path, problem), file=sys.stderr)
    sys.exit(1)
summary = check_evaluator(document) if kind == "evaluator" else check_researcher(document)
if errors:
    for line in errors:
        print("claude-code-new-functionality-check: INVALID %s" % line, file=sys.stderr)
    print("claude-code-new-functionality-check: INVALID %d problem(s) in %s — do not log anything from this file" % (len(errors), path), file=sys.stderr)
    sys.exit(1)
for line in overlong:
    print("claude-code-new-functionality-check: OVERLONG %s" % line, file=sys.stderr)
print("valid: %s%s" % (summary, "; %d over-long field(s) to reword while curating" % len(overlong) if overlong else ""))
PY
}

# -------------------------------------------------------------------- inventory
# What the config ACTUALLY contains, generated — so evaluators ground proposals in
# facts instead of in the model's memory of what a config usually looks like.

settings_report() {
    # Hooks, permissions, env, plugins from settings.json. Env VALUES are shown only
    # for 0/1/true/false: any other value, numeric ones included, may be an ID or a secret.
    local file="$CLAUDE_DIR/settings.json" tool="${NEW_FUNCTIONALITY_CHECK_JSON_TOOL:-}"
    [ -f "$file" ] || { emit "(no settings.json)"; return 0; }
    if [ -z "$tool" ]; then
        if command -v jq >/dev/null 2>&1; then tool="jq"; else tool="python"; fi
    fi
    if [ "$tool" = "jq" ]; then
        jq -r '
          def modern: [ (if has("if") then "if" else empty end), (if has("async") then "async" else empty end),
                        (if has("asyncRewake") then "asyncRewake" else empty end), (if has("args") then "args" else empty end),
                        (if has("timeout") then "timeout" else empty end) ] | join(",") | if . == "" then "-" else . end;
          # Exec form keeps the script path in args; without it the hook looks like a file nothing runs.
          def shown_command: ([.command // .type // "?"] + [(.args // [])[] | tostring]) | join(" ");
          "### Hook registrations (event | matcher | command | modern fields used)",
          ((.hooks // {}) | to_entries[] | .key as $event | .value[] | (.matcher // "*") as $matcher | .hooks[]
             | "\($event) | \($matcher) | \(shown_command) | \(modern)"),
          "", "### Settings",
          "top-level keys: \(keys | join(", "))",
          "permissions: defaultMode=\(.permissions.defaultMode // "unset") allow=\(.permissions.allow // [] | length) deny=\(.permissions.deny // [] | length) ask=\(.permissions.ask // [] | length)",
          ((.env // {}) | to_entries[] | "env \(.key)=" + (if (.value | tostring | test("^(0|1|true|false)$")) then (.value | tostring) else "<set>" end)),
          "", "### Enabled plugins",
          ((.enabledPlugins // {}) | to_entries[] | select(.value == true) | .key)' "$file"
        return $?
    fi
    find_python || die "$EXIT_USAGE" "cannot read settings.json: neither jq nor a working python was found"
    "$PYTHON_CMD" - "$file" <<'PY'
import json, re, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    settings = json.load(handle)
print("### Hook registrations (event | matcher | command | modern fields used)")
for event, groups in (settings.get("hooks") or {}).items():
    for group in groups:
        for hook in group.get("hooks", []):
            modern = [key for key in ("if", "async", "asyncRewake", "args", "timeout") if key in hook]
            # Exec form keeps the script path in args; without it the hook looks like a file nothing runs.
            shown_command = " ".join([hook.get("command") or hook.get("type") or "?"] + [str(arg) for arg in hook.get("args") or []])
            print("%s | %s | %s | %s" % (event, group.get("matcher", "*"), shown_command, ",".join(modern) or "-"))
print("")
print("### Settings")
print("top-level keys: %s" % ", ".join(sorted(settings.keys())))
permissions = settings.get("permissions") or {}
print("permissions: defaultMode=%s allow=%d deny=%d ask=%d" % (permissions.get("defaultMode", "unset"),
      len(permissions.get("allow") or []), len(permissions.get("deny") or []), len(permissions.get("ask") or [])))
for key, value in (settings.get("env") or {}).items():
    shown = str(value) if re.match(r"^(0|1|true|false)$", str(value)) else "<set>"
    print("env %s=%s" % (key, shown))
print("")
print("### Enabled plugins")
for key, value in (settings.get("enabledPlugins") or {}).items():
    if value is True:
        print(key)
PY
}

frontmatter_keys() {
    # frontmatter_keys <file> -> comma-separated top-level YAML keys, or empty when there is no frontmatter
    awk 'NR == 1 && $0 != "---" { exit }
         NR > 1 && $0 == "---" { exit }
         NR > 1 && /^[A-Za-z_-]+:/ { key = $0; sub(/:.*/, "", key); keys = (keys == "" ? key : keys "," key) }
         END { print keys }' "$1"
}

frontmatter_value() {
    # frontmatter_value <file> <key>
    awk -v want="$2" 'NR == 1 && $0 != "---" { exit }
         NR > 1 && $0 == "---" { exit }
         NR > 1 { key = $0; sub(/:.*/, "", key); if (key == want) { value = $0; sub(/^[^:]*:[ \t]*/, "", value); print value; exit } }' "$1"
}

claude_md_sections() {
    # claude_md_sections <file> -> the ## headings of a CLAUDE.md as one line, the map of the
    # system's subsystems: fenced lines skipped, control characters removed, each heading capped.
    find_python || { emit "(not listed: this needs a working python, and none was found)"; return 0; }
    "$PYTHON_CMD" - "$1" <<'PY'
import re, sys
HEADING_CAP, HEADINGS_MAX = 80, 60
headings, fenced = [], False
with open(sys.argv[1], encoding="utf-8", errors="replace") as handle:
    for line in handle:
        if line.lstrip().startswith("```"):
            fenced = not fenced
            continue
        if not fenced and line.startswith("## "):
            text = re.sub(r"\s+", " ", re.sub(r"[\x00-\x1f\x7f]", "", line[3:])).strip()
            headings.append(text[:HEADING_CAP])
print("; ".join(headings[:HEADINGS_MAX]) if headings else "(no ## headings)")
PY
}

system_layer_report() {
    # The rest of the system layer: MCP servers (configured, claude.ai connectors and plugin-
    # provided), installed plugins and marketplaces. Only an allowlist of fields is printed
    # (names, scopes, types, versions), masked and capped, so no URL, path, command, argument,
    # header or env value can reach the inventory. A missing or malformed file is reported,
    # never fatal. .claude.json lives in CLAUDE_CONFIG_DIR when that is set, else in HOME; the
    # override exists so the offline suite never reads the real one.
    if ! find_python; then
        emit "### MCP servers, plugins and marketplaces"
        emit "(not listed: this needs a working python, and none was found)"
        return 0
    fi
    "$PYTHON_CMD" - "${NEW_FUNCTIONALITY_CHECK_CLAUDE_JSON:-${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json}" "$CLAUDE_DIR" <<'PY'
import json, os, re, sys
claude_json, claude_dir = sys.argv[1], sys.argv[2]
NAME_CAP = 60
KNOWN_TYPES = ("stdio", "sse", "http", "ws")

def load(path):
    if not os.path.isfile(path):
        return None, "(none: no %s)" % os.path.basename(path)
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle), None
    except (OSError, ValueError, RecursionError):
        return None, "(unreadable)"

def safe(value):
    # Names only: anything outside a plain label alphabet is masked, and the length is capped.
    return re.sub(r"[^A-Za-z0-9 ._@+-]", "?", value)[:NAME_CAP] if isinstance(value, str) else "-"

def keys_of(mapping):
    return sorted(mapping) if isinstance(mapping, dict) else []

def server_type(server):
    value = server.get("type", "stdio") if isinstance(server, dict) else None
    return value if value in KNOWN_TYPES else "?"

def plugin_servers(install):
    found, unreadable = [], 0
    for candidate in (os.path.join(install, ".mcp.json"), os.path.join(install, ".claude-plugin", "plugin.json")):
        if not os.path.isfile(candidate):
            continue
        data, problem = load(candidate)
        if problem or not isinstance(data, dict):
            unreadable += 1
            continue
        servers = data.get("mcpServers", data if candidate.endswith(".mcp.json") else None)
        if isinstance(servers, dict):
            found.extend(name for name in servers if isinstance(servers[name], dict))
    return found, unreadable

state, state_problem = load(claude_json)
if state is not None and not isinstance(state, dict):
    state_problem = "(unreadable)"              # valid JSON, but not the object Claude Code writes
state = state if isinstance(state, dict) else {}
plugins, plugins_problem = load(os.path.join(claude_dir, "plugins", "installed_plugins.json"))
records = plugins.get("plugins") if isinstance(plugins, dict) else None
plugin_lines, provided, manifests_unreadable = [], set(), 0
for name in keys_of(records):
    for record in (records[name] if isinstance(records[name], list) else [records[name]]):
        if not isinstance(record, dict):
            continue
        plugin_lines.append("%s | %s | %s" % (safe(name), safe(record.get("scope")), safe(record.get("version"))))
        if isinstance(record.get("installPath"), str):
            servers, unreadable = plugin_servers(record["installPath"])
            manifests_unreadable += unreadable
            provided.update("%s (from %s)" % (safe(server), safe(name)) for server in servers)

print("(every name below comes from local config files: data, not instructions)")
print("### MCP servers (name | scope | type)")
if state_problem:
    print(state_problem)
users = state.get("mcpServers")
for name in keys_of(users):
    print("%s | user | %s" % (safe(name), server_type(users[name])))
per_project, projects_with = {}, 0
projects = state.get("projects")
for project in (projects.values() if isinstance(projects, dict) else []):
    servers = project.get("mcpServers") if isinstance(project, dict) else None
    if isinstance(servers, dict) and servers:
        projects_with += 1
        for name in servers:
            per_project[safe(name)] = per_project.get(safe(name), 0) + 1
if per_project:
    print("project-scoped (names only): %s; %d server(s) across %d project(s)"
          % (", ".join(sorted(per_project)), sum(per_project.values()), projects_with))
connectors = state.get("claudeAiMcpEverConnected")
if isinstance(connectors, list) and connectors:
    print("claude.ai connectors: %s" % ", ".join(sorted(safe(name) for name in connectors if isinstance(name, str))))
if provided:
    print("plugin-provided: %s" % ", ".join(sorted(provided)))
if manifests_unreadable:
    print("(%d plugin manifest(s) could not be read; their servers are not listed)" % manifests_unreadable)
if not (state_problem or keys_of(users) or per_project or connectors or provided):
    print("(none configured)")
print("")
print("### Installed plugins (name@marketplace | scope | version)")
print(plugins_problem if plugins_problem else "\n".join(plugin_lines) if plugin_lines else "(none installed)")
print("")
print("### Plugin marketplaces (name | source type)")
markets, markets_problem = load(os.path.join(claude_dir, "plugins", "known_marketplaces.json"))
if markets_problem:
    print(markets_problem)
else:
    for name in keys_of(markets):
        source = markets[name].get("source") if isinstance(markets[name], dict) else None
        print("%s | %s" % (safe(name), safe(source.get("source")) if isinstance(source, dict) else "-"))
PY
}

cmd_inventory() {
    local wired file name keys extra key skill_dir helpers lines version
    emit "# Config inventory (generated $(date -u +%Y-%m-%dT%H:%M:%SZ) by claude_code_new_functionality_check.sh — facts, not memory)"
    emit ""
    version="$( [ -f "$CLAUDE_DIR/.last-update-result.json" ] && json_path "$CLAUDE_DIR/.last-update-result.json" version_to 2>/dev/null | head -1 )"
    emit "Installed CLI (from the updater record): ${version:-unknown}"
    emit ""
    wired="$(settings_report)" || exit $?
    emit "$wired"
    emit ""
    emit "### Hook files on disk that NO registration runs"
    for file in "$CLAUDE_DIR"/hooks/*.sh; do
        [ -f "$file" ] || continue
        name="$(basename "$file")"
        case "$wired" in *"/hooks/$name"*) ;; *) emit "$name" ;; esac
    done
    emit ""
    emit "### Agents (name | model | tools | frontmatter keys beyond name/description/tools/model)"
    for file in "$CLAUDE_DIR"/agents/*.md; do
        [ -f "$file" ] || continue
        extra=""
        for key in $(frontmatter_keys "$file" | tr ',' ' '); do
            case "$key" in name|description|tools|model) ;; *) extra="${extra:+$extra,}$key" ;; esac
        done
        emit "$(basename "$file" .md) | $(frontmatter_value "$file" model) | $(frontmatter_value "$file" tools) | ${extra:--}"
    done
    emit ""
    emit "### Skills (name | frontmatter | lines | resources | helpers)"
    for skill_dir in "$CLAUDE_DIR"/skills/*/; do
        [ -f "$skill_dir/SKILL.md" ] || continue
        keys="$(frontmatter_keys "$skill_dir/SKILL.md")"
        helpers="$(cd "$skill_dir" && ls 2>/dev/null | grep -E '\.(sh|py)$' | tr '\n' ' ' | sed 's/ $//')"
        lines="$(wc -l < "$skill_dir/SKILL.md" | tr -d ' ')"
        emit "$(basename "$skill_dir") | frontmatter: ${keys:-none} | $lines lines | resources: $( [ -d "$skill_dir/resources" ] && echo yes || echo no ) | helpers: ${helpers:--}"
    done
    emit ""
    emit "### Global CLAUDE.md"
    if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
        emit "$(wc -l < "$CLAUDE_DIR/CLAUDE.md" | tr -d ' ') lines, $(wc -c < "$CLAUDE_DIR/CLAUDE.md" | tr -d ' ') bytes; imports: $(grep -o '^@[^ ]*' "$CLAUDE_DIR/CLAUDE.md" | tr '\n' ' ')"
        emit "sections (the map of the system's subsystems): $(claude_md_sections "$CLAUDE_DIR/CLAUDE.md")"
    else
        emit "(none)"
    fi
    emit ""
    system_layer_report
    emit ""
    emit "### Feature surfaces this config does not use at all"
    for name in $ABSENT_FEATURE_PATHS; do
        [ -e "$CLAUDE_DIR/$name" ] && continue
        # Directories are shown with a trailing slash; keybindings.json is a file.
        case "$name" in
            *.json) emit "$name" ;;
            *)      emit "$name/" ;;
        esac
    done
    return 0
}

# ------------------------------------------------------------- ledger bookkeeping

ledger_ids() {
    # ledger_ids <ledger.md> -> the IDs of its index rows, in file order
    [ -f "$1" ] || return 0
    awk -F'|' '{ id = $2; gsub(/[ \t]/, "", id); if (id ~ /^RW-[0-9]+$/) print id }' "$1"
}

cmd_next_id() {
    local highest
    highest="$(cat "$LEDGER_DIR/ledger.md" "$LEDGER_DIR/proposals.md" 2>/dev/null \
               | grep -o 'RW-[0-9][0-9]*' | sed 's/^RW-0*//' | awk 'BEGIN { best = 0 } $1 + 0 > best { best = $1 + 0 } END { print best }')"
    printf 'RW-%04d\n' $(( ${highest:-0} + 1 ))
}

cmd_snapshot() {
    local stamp dest name copied=0
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    dest="$LEDGER_DIR/archive/$stamp"
    for name in $LEDGER_FILES; do
        [ -f "$LEDGER_DIR/$name" ] || continue
        mkdir -p "$dest"
        cp -p "$LEDGER_DIR/$name" "$dest/$name"
        copied=$(( copied + 1 ))
    done
    if [ "$copied" -eq 0 ]; then emit "nothing to snapshot"; else emit "snapshot: $dest"; fi
    return 0
}

backup_target_dir() {
    # backup_target_dir [<dir>] -> the directory to write into: the argument, else BACKUP_DIR= in backup.conf
    local conf="$LEDGER_DIR/$BACKUP_CONF_NAME" line
    if [ -n "${1:-}" ]; then printf '%s\n' "$1"; return 0; fi
    [ -f "$conf" ] || return 1
    line="$(grep -E '^BACKUP_DIR=' "$conf" | tail -1)"
    [ -n "$line" ] || return 1
    # The file is hand-edited, possibly on Windows: drop a CR, surrounding blanks and one pair of quotes,
    # so the failure message never hides the byte that broke the path.
    line="${line#BACKUP_DIR=}"
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in
        \"*\") line="${line#\"}"; line="${line%\"}" ;;
        \'*\') line="${line#\'}"; line="${line%\'}" ;;
    esac
    [ -n "$line" ] || return 1
    printf '%s\n' "$line"
}

cmd_backup() {
    # backup [<dir>] — one dated tar.gz of the ledger, written somewhere that is NOT this disk's
    # only copy. Never overwrites and never deletes an earlier backup; a refused run writes nothing.
    # Exit 1 = nothing to do or a bad target; exit 2 = the archive could not be written.
    local target ledger_real target_real stamp dest scratch suffix=1 count
    [ -f "$LEDGER_DIR/ledger.md" ] || die "$EXIT_USAGE" "nothing to back up: no ledger at $LEDGER_DIR"
    target="$(backup_target_dir "${1:-}")" || die "$EXIT_USAGE" "no backup target: pass a directory, or put BACKUP_DIR=<dir> in $LEDGER_DIR/$BACKUP_CONF_NAME"
    [ -d "$target" ] && [ -w "$target" ] || die "$EXIT_USAGE" "backup target is not a writable directory: [$target]"
    ledger_real="$(cd "$LEDGER_DIR" && pwd -P)"; target_real="$(cd "$target" && pwd -P)"
    case "$target_real/" in
        "$ledger_real"/*) die "$EXIT_USAGE" "backup target is inside the ledger ($target) — that is not a copy off this disk, and tar would archive its own output" ;;
    esac
    stamp="${NEW_FUNCTIONALITY_CHECK_BACKUP_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
    scratch="$target/.${BACKUP_FILE_PREFIX}$$.tmp"
    trap 'rm -f "$scratch"' INT TERM
    # COPYFILE_DISABLE keeps macOS tar from adding ._* resource-fork entries. Both exclude spellings are
    # given because bsdtar and GNU tar match a "./"-prefixed member name by different rules.
    if ! COPYFILE_DISABLE=1 tar -czf "$scratch" -C "$LEDGER_DIR" --exclude "./$BACKUP_EXCLUDED_DIR" --exclude "$BACKUP_EXCLUDED_DIR" . 2>/dev/null; then
        rm -f "$scratch"
        die "$EXIT_PARTIAL" "backup failed: tar could not write into $target"
    fi
    if ! tar -tzf "$scratch" </dev/null 2>/dev/null | grep -q 'ledger\.md$'; then
        rm -f "$scratch"
        die "$EXIT_PARTIAL" "backup failed: the archive does not contain ledger.md"
    fi
    # mv -n never replaces an existing file: if the name was taken (even a moment ago), try the next one.
    dest="$target/${BACKUP_FILE_PREFIX}${stamp}.tar.gz"
    while :; do
        [ -e "$dest" ] || mv -n "$scratch" "$dest" 2>/dev/null
        [ -e "$scratch" ] || break
        suffix=$(( suffix + 1 ))
        [ "$suffix" -le "$BACKUP_MAX_NAME_TRIES" ] || { rm -f "$scratch"; die "$EXIT_PARTIAL" "backup failed: no free file name for stamp $stamp in $target"; }
        dest="$target/${BACKUP_FILE_PREFIX}${stamp}_${suffix}.tar.gz"
    done
    trap - INT TERM
    count="$(tar -tzf "$dest" </dev/null 2>/dev/null | grep -c -v '/$')"
    emit "backup: $dest ($count files)"
}

cmd_ledger_check() {
    # The ledger is hand-edited markdown, so its invariants are checked, not assumed:
    # unique ascending IDs, a known status, one detail block per row, and nothing
    # that existed at the last snapshot has disappeared (never delete).
    local ledger="$LEDGER_DIR/ledger.md" proposals="$LEDGER_DIR/proposals.md" problems=0 id status previous=0 number last_snapshot count=0
    [ -f "$ledger" ] || die "$EXIT_USAGE" "no ledger at $ledger"
    while IFS='|' read -r _ id status _; do
        id="$(printf '%s' "$id" | tr -d ' \t')"
        case "$id" in RW-*) ;; *) continue ;; esac
        case "${id#RW-}" in
            ''|*[!0-9]*)
                # "10#12abc" is a fatal arithmetic error in bash: it would end the loop and
                # silently skip every later row, so the shape is checked before the math.
                printf 'claude-code-new-functionality-check: LEDGER %s is not a well-formed id (RW- followed by digits only)\n' "$id" >&2
                problems=$(( problems + 1 )); continue ;;
        esac
        count=$(( count + 1 ))
        number=$(( 10#${id#RW-} ))
        if [ "$number" -le "$previous" ]; then
            printf 'claude-code-new-functionality-check: LEDGER %s is duplicated or out of order (ids only ever ascend)\n' "$id" >&2
            problems=$(( problems + 1 ))
        fi
        previous="$number"
        status="$(printf '%s' "$status" | awk '{ print $1 }')"
        case " $STATUS_VOCABULARY " in
            *" $status "*) ;;
            *) printf 'claude-code-new-functionality-check: LEDGER %s has status "%s" (allowed: %s)\n' "$id" "$status" "$STATUS_VOCABULARY" >&2
               problems=$(( problems + 1 )) ;;
        esac
        if ! grep -q "^### $id\b" "$proposals" 2>/dev/null && ! grep -q "^### $id " "$proposals" 2>/dev/null; then
            printf 'claude-code-new-functionality-check: LEDGER %s has an index row but no detail block in proposals.md\n' "$id" >&2
            problems=$(( problems + 1 ))
        fi
    done < "$ledger"
    last_snapshot="$(ls -d "$LEDGER_DIR"/archive/*/ 2>/dev/null | LC_ALL=C sort | tail -1)"
    if [ -n "$last_snapshot" ] && [ -f "$last_snapshot/ledger.md" ]; then
        for id in $(ledger_ids "$last_snapshot/ledger.md"); do
            if ! ledger_ids "$ledger" | grep -q "^$id$"; then
                printf 'claude-code-new-functionality-check: LEDGER %s existed at the last snapshot and is gone — rows are never deleted\n' "$id" >&2
                problems=$(( problems + 1 ))
            fi
        done
    fi
    [ "$problems" -eq 0 ] || return 1
    emit "ledger-check: ok ($count proposals)"
}

cmd_ledger_add() {
    # ledger-add <curated.json> — render curated PROPOSE / RISK-WATCH candidates into the
    # ledger. The main session decides WHAT goes in; the helper decides how it is written,
    # so ids, table cells, and blocks always have the shape next-id and ledger-check expect.
    local curated="${1:-}"
    [ -f "$curated" ] || die "$EXIT_USAGE" "curated candidates file not found: $curated"
    find_python || die "$EXIT_USAGE" "ledger-add needs a working python (none found)"
    mkdir -p "$LEDGER_DIR"
    "$PYTHON_CMD" - "$curated" "$LEDGER_DIR" "$(today_utc)" "$FIELD_CAPS_JSON" "$BREADTHS" <<'PY'
import json, os, re, sys
curated_path, ledger_dir, today, CAPS = sys.argv[1], sys.argv[2], sys.argv[3], json.loads(sys.argv[4])
BREADTHS = set(sys.argv[5].split())
ledger_path = os.path.join(ledger_dir, "ledger.md")
proposals_path = os.path.join(ledger_dir, "proposals.md")
INDEX_HEADER = ("| ID | status | target | feature_key | title | upstream | logged | decided |\n"
                "|---|---|---|---|---|---|---|---|\n")
SKELETON = ("# New-Functionality Check Ledger\n\n## Coverage\n\n"
            "| source | covered through | last success (UTC) | consecutive failures |\n|---|---|---|---|\n\n"
            "## Proposal index\n\n" + INDEX_HEADER + "\n## Run log\n\n")

def cell(text):
    """One table cell: a pipe or a line break inside it would break the table."""
    return re.sub(r"\s+", " ", str(text)).replace("|", "/").strip()

def one_line(text):
    return re.sub(r"\s+", " ", str(text)).strip()

with open(curated_path, encoding="utf-8") as handle:
    curated = json.load(handle)
if not isinstance(curated, list) or not all(isinstance(item, dict) for item in curated):
    sys.exit("claude-code-new-functionality-check: ERROR ledger-add needs a JSON list of candidate objects")

# The write gate: every capped field is checked BEFORE anything is written, so a refused
# batch leaves the ledger exactly as it was.
refused = []
for number, item in enumerate(curated, 1):
    fields = dict(item); fields.update(item.get("upstream") or {})
    for key, value in fields.items():
        if isinstance(value, str) and key in CAPS and len(value) > CAPS[key]:
            refused.append("item %d: %s is %d characters (cap %d)" % (number, key, len(value), CAPS[key]))
    # A new-capability proposal carries both lens fields; half of one is a curation slip.
    if ("capability" in item) != ("breadth" in item):
        refused.append("item %d: capability and breadth go together (a new-capability proposal carries both)" % number)
    elif "breadth" in item and item["breadth"] not in BREADTHS:
        refused.append("item %d: breadth must be one of %s" % (number, sorted(BREADTHS)))
if refused:
    for line in refused:
        print("claude-code-new-functionality-check: ERROR %s" % line, file=sys.stderr)
    sys.exit("claude-code-new-functionality-check: ERROR nothing was written — fix the field(s) above and run ledger-add again")

ledger = open(ledger_path, encoding="utf-8").read() if os.path.exists(ledger_path) else SKELETON
proposals = open(proposals_path, encoding="utf-8").read() if os.path.exists(proposals_path) else "# New-Functionality Check — proposal details\n"
if "## Run log" not in ledger or "## Proposal index" not in ledger:
    sys.exit("claude-code-new-functionality-check: ERROR %s has lost its '## Proposal index' / '## Run log' sections" % ledger_path)

existing = set()
for line in ledger.splitlines():
    parts = [part.strip() for part in line.split("|")]
    if len(parts) > 5 and re.match(r"^RW-\d+$", parts[1]):
        existing.add((parts[4], parts[3]))                       # (feature_key, target)
highest = max([int(number) for number in re.findall(r"RW-(\d+)", ledger + proposals)] or [0])

rows, blocks = [], []
for item in curated:
    key = (cell(item.get("feature_key", "")), cell(item.get("target_type", "other")))
    title = cell(item.get("title", "(untitled)"))
    if key in existing:
        print("skipped (already in the ledger): %s | %s" % (key[0], title))
        continue
    existing.add(key)
    highest += 1
    ident = "RW-%04d" % highest
    upstream = item.get("upstream") or {}
    new_capability = "capability" in item
    marker = "[RISK] " if item.get("verdict") == "RISK-WATCH" else "[NEW] " if new_capability else ""
    shown_title = marker + title
    rows.append("| %s | proposed | %s | %s | %s | %s | %s | |" % (ident, key[1], key[0], shown_title, cell(upstream.get("ref", "")), today))
    paths = ", ".join("`%s`" % one_line(path) for path in item.get("target_paths") or [])
    docs = (" · docs: %s" % one_line(upstream["docs_url"])) if upstream.get("docs_url") else ""
    # The slice-local launch id (L01…) is never written: it means nothing outside its slice.
    lens_lines = ["- **New capability:** %s" % one_line(item["capability"]),
                  "- **Breadth:** %s" % one_line(item["breadth"])] if new_capability else []
    blocks.append("\n".join([
        "", "### %s · %s · %s" % (ident, key[1], shown_title), "",
        "- **Status:** proposed (logged %s)" % today,
        "- **Upstream:** %s %s · %s%s" % (one_line(upstream.get("source", "")), one_line(upstream.get("ref", "")), one_line(upstream.get("url", "")), docs),
        "  > %s" % one_line(upstream.get("quote", ""))] + lens_lines + [
        "- **Today:** %s%s" % (one_line(item.get("today", "")), (" (%s)" % paths) if paths else ""),
        "- **Proposed change:** %s" % one_line(item.get("proposed_change", "")),
        "- **Benefit / effort / risk:** %s / %s / %s · **Sensitive:** %s" % (
            item.get("benefit", "?"), item.get("effort", "?"), item.get("risk", "?"),
            "YES — accept only after a walk-through" if item.get("sensitive") else "no"),
        "- **Verify before adopting:** %s" % one_line(item.get("verify_before_adopting", "")),
        "- **History:** %s proposed" % today, ""]))
    print("%s | %s" % (ident, shown_title))

def replace_file(path, content):
    # Write beside the target and rename: a crash mid-write can never truncate the ledger.
    scratch = path + ".tmp"
    with open(scratch, "w", encoding="utf-8") as handle:
        handle.write(content)
    os.replace(scratch, path)

if rows:
    head, tail = ledger.split("## Run log", 1)
    ledger = head.rstrip("\n") + "\n" + "\n".join(rows) + "\n\n## Run log" + tail
    replace_file(proposals_path, proposals.rstrip("\n") + "\n" + "".join(blocks))
    replace_file(ledger_path, ledger)
elif not os.path.exists(ledger_path):
    replace_file(ledger_path, ledger)
PY
}

cmd_ledger_status() {
    # ledger-status <RW-id> <status> [<detail>] — a decision lives in two places (the index
    # row and the detail block). Typing both by hand, 39 times, is how they drift apart, so
    # the helper changes both or neither. WHO may decide is the skill's rule, not this
    # command's: statuses move on the user's explicit word only.
    local ident="${1:-}" status="${2:-}" detail="${3:-}"
    case "$ident" in RW-*) ;; *) die "$EXIT_USAGE" "ledger-status needs an id like RW-0007 (got: $ident)" ;; esac
    case "${ident#RW-}" in ''|*[!0-9]*) die "$EXIT_USAGE" "ledger-status needs an id like RW-0007 (got: $ident)" ;; esac
    case " $STATUS_VOCABULARY " in
        *" $status "*) ;;
        *) die "$EXIT_USAGE" "status must be one of: $STATUS_VOCABULARY (got: $status)" ;;
    esac
    find_python || die "$EXIT_USAGE" "ledger-status needs a working python (none found)"
    "$PYTHON_CMD" - "$LEDGER_DIR" "$ident" "$status" "$detail" "$(today_utc)" <<'PY'
import os, re, sys
ledger_dir, ident, status, detail, today = sys.argv[1:6]
NEEDS_DETAIL = {"declined": "a why", "deferred": "an until (a date or a condition)", "applied": "its evidence", "obsolete": "the superseding evidence"}
DETAIL_CAP = 200
detail = re.sub(r"\s+", " ", detail).replace("|", "/").strip()
if status in NEEDS_DETAIL and not detail:
    sys.exit("claude-code-new-functionality-check: ERROR a %s decision needs %s" % (status, NEEDS_DETAIL[status]))
if len(detail) > DETAIL_CAP:
    sys.exit("claude-code-new-functionality-check: ERROR the detail is %d characters (cap %d)" % (len(detail), DETAIL_CAP))
shown = status + (" — " + detail if detail else "")

ledger_path, proposals_path = os.path.join(ledger_dir, "ledger.md"), os.path.join(ledger_dir, "proposals.md")
try:
    ledger = open(ledger_path, encoding="utf-8").read()
    proposals = open(proposals_path, encoding="utf-8").read()
except OSError as problem:
    sys.exit("claude-code-new-functionality-check: ERROR cannot read the ledger: %s" % problem)

rows = [line for line in ledger.splitlines() if re.match(r"^\|\s*%s\s*\|" % re.escape(ident), line)]
if len(rows) != 1:
    sys.exit("claude-code-new-functionality-check: ERROR %s has %d index rows (expected exactly 1)" % (ident, len(rows)))
cells = rows[0].split("|")
if len(cells) != 10:
    sys.exit("claude-code-new-functionality-check: ERROR the index row for %s does not have 8 columns" % ident)
cells[2], cells[8] = " %s " % shown, " %s " % today
ledger = ledger.replace(rows[0], "|".join(cells), 1)

block = re.search(r"(?ms)^### %s\b.*?(?=^### RW-|\Z)" % re.escape(ident), proposals)
if not block:
    sys.exit("claude-code-new-functionality-check: ERROR %s has no detail block in proposals.md" % ident)
body = block.group(0)
new_body, status_hits = re.subn(r"(?m)^- \*\*Status:\*\* .*$", "- **Status:** %s (decided %s)" % (shown, today), body, count=1)
new_body, history_hits = re.subn(r"(?m)^(- \*\*History:\*\* .*)$", lambda match: "%s · %s %s" % (match.group(1), today, shown), new_body, count=1)
if status_hits != 1 or history_hits != 1:
    sys.exit("claude-code-new-functionality-check: ERROR the detail block for %s has no Status or History line" % ident)
proposals = proposals[:block.start()] + new_body + proposals[block.end():]

# Both files are written beside their targets first; only then is either one replaced.
scratch = [(ledger_path + ".tmp", ledger_path, ledger), (proposals_path + ".tmp", proposals_path, proposals)]
for temporary, _, content in scratch:
    with open(temporary, "w", encoding="utf-8") as handle:
        handle.write(content)
for temporary, final, _ in scratch:
    os.replace(temporary, final)
print("%s -> %s (decided %s)" % (ident, shown, today))
PY
}

path_mtime_epoch() {
    # GNU stat first: BSD stat rejects -c outright, whereas GNU stat would read "-f %m"
    # as "filesystem status" and print the wrong thing.
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

stamp_lock() {
    # Written beside the final name and renamed, so a reader never sees a half-written stamp.
    date +%s > "$1/taken_epoch.tmp.$$" && mv -f "$1/taken_epoch.tmp.$$" "$1/taken_epoch"
}

cmd_lock() {
    # mkdir is atomic, so two sessions that were both told a sweep is due cannot
    # both take it. A lock older than LOCK_STALE_SECS is a crashed sweep: break it.
    local lock="$LEDGER_DIR/.lock" taken now
    mkdir -p "$LEDGER_DIR"
    if mkdir "$lock" 2>/dev/null; then
        stamp_lock "$lock"
        emit "lock: taken"
        return 0
    fi
    now="$(date +%s)"
    taken="$(cat "$lock/taken_epoch" 2>/dev/null)"
    # mkdir is atomic but the timestamp write is a second step: a sweep killed between
    # the two leaves a lock with no timestamp. Its directory mtime stands in; if even
    # that is unreadable the lock counts as FRESH — refusing is the safe direction.
    case "$taken" in ''|*[!0-9]*) taken="$(path_mtime_epoch "$lock")" ;; esac
    case "$taken" in ''|*[!0-9]*) taken="$now" ;; esac
    if [ $(( now - taken )) -ge "$LOCK_STALE_SECS" ]; then
        warn "breaking a stale sweep lock (taken $(( now - taken ))s ago)"
        stamp_lock "$lock"
        emit "lock: taken (stale lock broken)"
        return 0
    fi
    printf 'claude-code-new-functionality-check: ERROR another sweep holds the lock (taken %ss ago) — do not start a second one\n' "$(( now - taken ))" >&2
    return 1
}

cmd_unlock() {
    rm -rf "$LEDGER_DIR/.lock"
    emit "lock: released"
}

# ------------------------------------------------------------------------ main
main() {
    local sub="${1:-}"
    [ $# -gt 0 ] && shift
    case "$sub" in
        digests)      cmd_digests "$@" ;;
        new-digests)  cmd_new_digests "$@" ;;
        changelog-since) cmd_changelog_since "$@" ;;
        fetch)        cmd_fetch "$@" ;;
        watch-diff)   cmd_watch_diff "$@" ;;
        watch-commit) cmd_watch_commit "$@" ;;
        launches)     cmd_launches "$@" ;;
        tracked-issues) cmd_tracked_issues "$@" ;;
        issue-status)   cmd_issue_status "$@" ;;
        issue-evidence) cmd_issue_evidence "$@" ;;
        verify-quote)   cmd_verify_quote "$@" ;;
        verify-lead)    cmd_verify_lead "$@" ;;
        verify-candidates) cmd_verify_candidates "$@" ;;
        scrub-check)    cmd_scrub_check "$@" ;;
        validate-candidates) cmd_validate_candidates "$@" ;;
        save-result)  cmd_save_result "$@" ;;
        ledger-status) cmd_ledger_status "$@" ;;
        inventory)      cmd_inventory "$@" ;;
        next-id)        cmd_next_id "$@" ;;
        snapshot)       cmd_snapshot "$@" ;;
        backup)         cmd_backup "$@" ;;
        ledger-check)   cmd_ledger_check "$@" ;;
        ledger-add)     cmd_ledger_add "$@" ;;
        lock)           cmd_lock "$@" ;;
        unlock)         cmd_unlock "$@" ;;
        _classify)    cmd_classify "$@" ;;
        _host-allowed) cmd_host_allowed "$@" ;;
        _retry-after) cmd_retry_after "$@" ;;
        -h|--help)    print_usage; exit 0 ;;
        '')           print_usage >&2; exit "$EXIT_USAGE" ;;
        *)            die "$EXIT_USAGE" "unknown subcommand: $sub (try --help)" ;;
    esac
}

main "$@"
