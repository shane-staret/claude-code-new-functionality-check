#!/bin/bash
# test-claude-code-new-functionality-check-helper.sh — offline tests for skills/claude-code-new-functionality-check/claude_code_new_functionality_check.sh
# Verifies: What's New index parsing (numeric year/week ordering, missing weeks,
# format drift = loud parse error), changelog slicing in BOTH upstream formats
# (numeric semver, non-contiguous versions, --no-fixed), fetch classification and
# bounded retries (file:// fixtures, a refused localhost port for the transient
# path, fallback chain, never clobbering a good cached copy), watched-page diffs,
# release channels, upstream-issue tracking, the config inventory (no env values
# leaked), and ledger bookkeeping (next-id, snapshot). Fixtures are generated
# inline; no network is ever touched. bash-3.2-safe.

set -u
HELPER="$(cd "$(dirname "$0")/../.." && pwd)/skills/claude-code-new-functionality-check/claude_code_new_functionality_check.sh"
TMPDIR_T="$(mktemp -d /tmp/claude-code-new-functionality-check-helper-test.XXXXXX)"
CACHE="$TMPDIR_T/cache"
LEDGER_DIR="$TMPDIR_T/ledger"
FAKE_CLAUDE="$TMPDIR_T/dot-claude"
SRC="$TMPDIR_T/src"
mkdir -p "$CACHE" "$LEDGER_DIR" "$FAKE_CLAUDE" "$SRC"

PASS=0
FAIL=0

h() {
    # h [VAR=val ...] bash "$HELPER" <subcommand> [args...] — sandboxed environment.
    env "NEW_FUNCTIONALITY_CHECK_CACHE_DIR=$CACHE" \
        "CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$LEDGER_DIR" \
        "NEW_FUNCTIONALITY_CHECK_CLAUDE_DIR=$FAKE_CLAUDE" \
        "NEW_FUNCTIONALITY_CHECK_RETRY_BASE_SECS=0" "$@"
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
        *"$2"*) FAIL=$((FAIL+1)); echo "FAIL: $1 (expected NOT to contain [$2])" ;;
        *) PASS=$((PASS+1)); echo "PASS: $1" ;;
    esac
}

# 0. The helper parses. (The SH5 suite's bash -n sweep covers hooks/ only, and this
#    script lives under skills/, so nothing else would catch a syntax error.)
if bash -n "$HELPER" 2>/dev/null; then check "helper is syntax-clean" "ok" "ok"; else check "helper is syntax-clean" "ok" "syntax error"; fi

# ---------------------------------------------------------------------------
# What's New index: digests / new-digests
# ---------------------------------------------------------------------------
cat > "$CACHE/whats-new.md" <<'IDX'
> ## Documentation Index
# What's new

<Update label="Week 9" description="March 1–5, 2027" tags={["v2.2.10–v2.2.19"]}>
  **Later year, unpadded week**: text

  [Read the Week 9 digest →](/docs/en/whats-new/2027-w9)
</Update>

<Update label="Week 37" description="September 7–11, 2026" tags={["v2.1.263–v2.1.269"]}>
  **`claude plugin eval`**: text

  [Read the Week 37 digest →](/docs/en/whats-new/2026-w37)
</Update>

<Update label="Week 36" description="August 31 – September 4, 2026" tags={["v2.1.251–v2.1.261"]}>
  **Claude Fable 5.1**: text

  [Read the Week 36 digest →](/docs/en/whats-new/2026-w36)
</Update>

<Update label="Week 30" description="July 20–24, 2026" tags={["v2.1.214–v2.1.219"]}>
  **Claude Opus 5**: text (week 31 was never published)

  [Read the Week 30 digest →](/docs/en/whats-new/2026-w30)
</Update>

<Update label="Week 9" description="February 23–27, 2026" tags={["v2.1.50–v2.1.55"]}>
  **Same-year unpadded week**: text

  [Read the Week 9 digest →](/docs/en/whats-new/2026-w9)
</Update>
IDX

OUT=$(h bash "$HELPER" digests); RC=$?
check "digests exits 0" "0" "$RC"
check "digests lists every entry" "5" "$(printf '%s\n' "$OUT" | grep -c .)"
check_contains "digest line carries slug, label, dates, versions" "2026-w37|Week 37|September 7–11, 2026|v2.1.263–v2.1.269" "$OUT"

OUT=$(h bash "$HELPER" new-digests 2026-w36)
check "new-digests is numeric, not lexicographic (2026-w9 is OLD, 2027-w9 is NEW)" "2027-w9 2026-w37" "$(printf '%s' "$OUT" | tr '\n' ' ' | sed 's/ $//')"
OUT=$(h bash "$HELPER" new-digests 2026-w30)
check "a never-published week (w31) is simply absent" "2027-w9 2026-w37 2026-w36" "$(printf '%s' "$OUT" | tr '\n' ' ' | sed 's/ $//')"
OUT=$(h bash "$HELPER" new-digests 2027-w9); RC=$?
check "nothing newer prints nothing" "" "$OUT"
check "nothing newer still exits 0" "0" "$RC"
OUT=$(h bash "$HELPER" new-digests none)
check "new-digests none lists everything (bootstrap)" "5" "$(printf '%s\n' "$OUT" | grep -c .)"
h bash "$HELPER" new-digests week37 >/dev/null 2>&1
check "a malformed slug is a usage error" "1" "$?"

# Format drift must be LOUD: a non-empty index that parses to zero digests is a
# parse error (exit 3), never "nothing new".
printf '# What is new\n\n<Release name="Week 37">renamed tags</Release>\n' > "$TMPDIR_T/drifted.md"
OUT=$(h bash "$HELPER" digests "$TMPDIR_T/drifted.md" 2>&1); RC=$?
check "format drift in the index exits 3" "3" "$RC"
check_contains "format drift explains itself" "parse error" "$OUT"
h bash "$HELPER" digests "$TMPDIR_T/missing.md" >/dev/null 2>&1
check "a missing index file is a precondition error" "1" "$?"

# ---------------------------------------------------------------------------
# Changelog slicing: changelog-since (both upstream formats)
# ---------------------------------------------------------------------------
cat > "$TMPDIR_T/changelog-docs.md" <<'DOCS'
# Claude Code changelog

> Release notes for Claude Code.

<Update label="2.1.278" description="September 19, 2026">
  * Changed auto mode to default to the server-side classifier
  * Added an `Auto mode server` row to `/status`
</Update>

<Update label="2.1.277" description="September 18, 2026">
  * Added AGENTS.md support
  * Fixed a headless hang after an internal error
  * Improved startup time
</Update>

<Update label="2.1.275" description="September 17, 2026">
  * Added claude.ai skill sync
  * Fixed a crash on resume
</Update>

<Update label="2.1.100" description="April 10, 2026">
  * Added the hundredth thing
</Update>

<Update label="2.1.99" description="April 9, 2026">
  * Added the ninety-ninth thing
</Update>
DOCS
cat > "$TMPDIR_T/changelog-raw.md" <<'RAW'
# Changelog

## 2.1.278

- Changed auto mode to default to the server-side classifier
- Added an `Auto mode server` row to `/status`

## 2.1.277

- Added AGENTS.md support
- Fixed a headless hang after an internal error
- Improved startup time

## 2.1.275

- Added claude.ai skill sync
- Fixed a crash on resume

## 2.1.100

- Added the hundredth thing

## 2.1.99

- Added the ninety-ninth thing
RAW

versions_of() { printf '%s\n' "$1" | grep '^## ' | sed 's/^## //; s/ (.*//' | tr '\n' ' ' | sed 's/ $//'; }

OUT=$(h bash "$HELPER" changelog-since 2.1.99 --file "$TMPDIR_T/changelog-docs.md"); RC=$?
check "changelog-since exits 0" "0" "$RC"
check "versions compare numerically (2.1.100 > 2.1.99) — docs format" "2.1.278 2.1.277 2.1.275 2.1.100" "$(versions_of "$OUT")"
check_contains "docs format keeps the release date" "## 2.1.278 (September 19, 2026)" "$OUT"
check_contains "docs bullets are normalized to '- '" "- Added AGENTS.md support" "$OUT"
check_absent "MDX wrapper tags never leak into the slice" "</Update>" "$OUT"

OUT=$(h bash "$HELPER" changelog-since 2.1.99 --file "$TMPDIR_T/changelog-raw.md")
check "versions compare numerically — raw format" "2.1.278 2.1.277 2.1.275 2.1.100" "$(versions_of "$OUT")"
check_contains "raw bullets pass through" "- Added AGENTS.md support" "$OUT"

OUT=$(h bash "$HELPER" changelog-since 2.1.276 --file "$TMPDIR_T/changelog-docs.md")
check "a version that was never published still slices correctly" "2.1.278 2.1.277" "$(versions_of "$OUT")"

OUT=$(h bash "$HELPER" changelog-since 2.1.275 2.1.277 --file "$TMPDIR_T/changelog-raw.md")
check "an upper bound is inclusive" "2.1.277" "$(versions_of "$OUT")"

OUT=$(h bash "$HELPER" changelog-since 0.0.0 --file "$TMPDIR_T/changelog-raw.md")
check "since 0.0.0 returns every version" "2.1.278 2.1.277 2.1.275 2.1.100 2.1.99" "$(versions_of "$OUT")"

OUT=$(h bash "$HELPER" changelog-since 2.1.278 --file "$TMPDIR_T/changelog-raw.md"); RC=$?
check "nothing newer prints nothing" "" "$OUT"
check "nothing newer exits 0" "0" "$RC"

OUT=$(h bash "$HELPER" changelog-since 2.1.99 --no-fixed --file "$TMPDIR_T/changelog-docs.md")
check_absent "--no-fixed drops Fixed bullets" "Fixed" "$OUT"
check_contains "--no-fixed keeps Added bullets" "- Added AGENTS.md support" "$OUT"
check_contains "--no-fixed keeps Improved bullets" "- Improved startup time" "$OUT"

cp "$TMPDIR_T/changelog-raw.md" "$CACHE/changelog.md"
OUT=$(h bash "$HELPER" changelog-since 2.1.277)
check "the cached changelog is the default input" "2.1.278" "$(versions_of "$OUT")"

h bash "$HELPER" changelog-since latest --file "$TMPDIR_T/changelog-raw.md" >/dev/null 2>&1
check "a non-version argument is a usage error" "1" "$?"
h bash "$HELPER" changelog-since 2.1.99 --file "$TMPDIR_T/nope.md" >/dev/null 2>&1
check "a missing changelog file is a precondition error" "1" "$?"
printf '# Changelog\n\n### v2.1.278 - renamed heading style\n- Added x\n' > "$TMPDIR_T/changelog-drifted.md"
OUT=$(h bash "$HELPER" changelog-since 2.1.99 --file "$TMPDIR_T/changelog-drifted.md" 2>&1); RC=$?
check "format drift in the changelog exits 3" "3" "$RC"
check_contains "changelog format drift explains itself" "parse error" "$OUT"

# ---------------------------------------------------------------------------
# Fetch classification: a pure function, so every HTTP branch is testable offline.
# (Measured on this Mac: curl --fail on a plain 404 exits 56, a "network" code —
# so the HTTP status decides first and the curl exit code only when there is none.)
# ---------------------------------------------------------------------------
classify() { h bash "$HELPER" _classify "$@"; }
check "200 is ok"                                   "ok"           "$(classify 0 200)"
check "a non-HTTP scheme (file://) success is ok"    "ok"           "$(classify 0 000)"
check "404 is permanent even when curl exits 56"     "permanent"    "$(classify 56 404)"
check "404 with a clean exit is permanent"           "permanent"    "$(classify 0 404)"
check "401 is permanent (never retry auth errors)"   "permanent"    "$(classify 0 401)"
check "408 is transient"                             "transient"    "$(classify 0 408)"
check "429 is transient"                             "transient"    "$(classify 0 429)"
check "500 is transient"                             "transient"    "$(classify 0 500)"
check "503 is transient"                             "transient"    "$(classify 22 503)"
check "501 is permanent (the 5xx exception)"         "permanent"    "$(classify 0 501)"
check "GitHub API 403 is a rate limit, not a verdict" "rate-limited" "$(classify 0 403 api.github.com)"
check "GitHub API 429 is a rate limit"               "rate-limited" "$(classify 0 429 api.github.com)"
check "a 403 anywhere else is permanent"             "permanent"    "$(classify 0 403 code.claude.com)"
check "DNS failure is transient"                     "transient"    "$(classify 6 000)"
check "connection refused is transient"              "transient"    "$(classify 7 000)"
check "timeout is transient"                         "transient"    "$(classify 28 000)"
check "a partial transfer with a 200 is transient"   "transient"    "$(classify 18 200)"
check "a missing file:// target is permanent"        "permanent"    "$(classify 37 000)"
check "an unsupported protocol is permanent"         "permanent"    "$(classify 1 000)"
check "a redirect we refused to follow is permanent" "permanent"    "$(classify 0 301)"
h bash "$HELPER" _classify 0 >/dev/null 2>&1
check "_classify needs both arguments" "1" "$?"

# ---------------------------------------------------------------------------
# fetch: one http_get for every source; file:// fixtures stand in for the network
# ---------------------------------------------------------------------------
file_url() {
    # Native Windows curl gets no MSYS path translation inside a URL, so Git Bash needs cygpath.
    if command -v cygpath >/dev/null 2>&1; then printf 'file:///%s' "$(cygpath -m "$1")"; else printf 'file://%s' "$1"; fi
}
FCACHE="$TMPDIR_T/fetch-cache"
mkdir -p "$SRC/whats-new"
cat > "$SRC/whats-new.md" <<'IDX'
# What's new
<Update label="Week 37" description="September 7–11, 2026" tags={["v2.1.263–v2.1.269"]}>
  [Read the Week 37 digest →](/docs/en/whats-new/2026-w37)
</Update>
<Update label="Week 36" description="August 31 – September 4, 2026" tags={["v2.1.251–v2.1.261"]}>
  [Read the Week 36 digest →](/docs/en/whats-new/2026-w36)
</Update>
<Update label="Week 30" description="July 20–24, 2026" tags={["v2.1.214–v2.1.219"]}>
  [Read the Week 30 digest →](/docs/en/whats-new/2026-w30)
</Update>
IDX
for W in 2026-w37 2026-w36 2026-w30; do printf '# %s\n\noriginal digest body\n' "$W" > "$SRC/whats-new/$W.md"; done
cp "$TMPDIR_T/changelog-docs.md" "$SRC/changelog.md"
cp "$TMPDIR_T/changelog-raw.md"  "$SRC/CHANGELOG-raw.md"
cp "$TMPDIR_T/changelog-raw.md"  "$SRC/local-cache-changelog.md"
printf '# Claude Code Docs\n\n- [Hooks](https://code.claude.com/docs/en/hooks.md): hooks\n- [Skills](https://code.claude.com/docs/en/skills.md): skills\n' > "$SRC/llms.txt"
printf '# Best practices\n\nVerify your work.\n' > "$SRC/best-practices.md"
printf '{"name":"official","plugins":[{"name":"superpowers"},{"name":"claude-code-setup"}]}\n' > "$SRC/marketplace.json"
printf '{"name":"@anthropic-ai/claude-code","version":"2.1.278"}\n' > "$SRC/npm-latest.json"
cat > "$SRC/support.html" <<'HTML'
<html><head><script>var junk = "<h3>not content</h3>";</script><style>h3{color:red}</style></head>
<body><article><h2>September 2026</h2><h3 id="h1">September 15, 2026</h3>
<p><b>Launching Salesforce in Claude (beta)</b></p><p>A plugin with 37 pre-built sales skills &amp; more.</p></article></body></html>
HTML

fetch_env() {
    # fetch_env [VAR=val ...] — every source pointed at the fixture tree; later assignments win.
    h "NEW_FUNCTIONALITY_CHECK_CACHE_DIR=$FCACHE" "NEW_FUNCTIONALITY_CHECK_CURL_PROTO==https,http,file" \
      "NEW_FUNCTIONALITY_CHECK_URL_INDEX=$(file_url "$SRC/whats-new.md")" \
      "NEW_FUNCTIONALITY_CHECK_URL_DIGEST_BASE=$(file_url "$SRC/whats-new")" \
      "NEW_FUNCTIONALITY_CHECK_URL_CHANGELOG=$(file_url "$SRC/changelog.md")" \
      "NEW_FUNCTIONALITY_CHECK_URL_CHANGELOG_MIRROR=$(file_url "$SRC/CHANGELOG-raw.md")" \
      "NEW_FUNCTIONALITY_CHECK_LOCAL_CHANGELOG=$SRC/local-cache-changelog.md" \
      "NEW_FUNCTIONALITY_CHECK_URL_DOCS_INDEX=$(file_url "$SRC/llms.txt")" \
      "NEW_FUNCTIONALITY_CHECK_URL_BEST_PRACTICES=$(file_url "$SRC/best-practices.md")" \
      "NEW_FUNCTIONALITY_CHECK_URL_MARKETPLACE=$(file_url "$SRC/marketplace.json")" \
      "NEW_FUNCTIONALITY_CHECK_URL_NPM_LATEST=$(file_url "$SRC/npm-latest.json")" \
      "NEW_FUNCTIONALITY_CHECK_URL_SUPPORT_NOTES=$(file_url "$SRC/support.html")" \
      "NEW_FUNCTIONALITY_CHECK_RETRY_ATTEMPTS=2" "$@"
}

# Happy path.
OUT=$(fetch_env bash "$HELPER" fetch 2>"$TMPDIR_T/fetch.err"); RC=$?
check "fetch exits 0 when every source succeeds" "0" "$RC"
for F in whats-new.md changelog.md digests/2026-w37.md digests/2026-w36.md digests/2026-w30.md \
         llms.txt best-practices.md marketplace.json npm-latest.json support-release-notes.html support-release-notes.txt; do
    if [ -s "$FCACHE/$F" ]; then check "fetch cached $F" "yes" "yes"; else check "fetch cached $F" "yes" "missing"; fi
done
check_contains "the table names the core index" "whats-new-index | core | ok" "$OUT"
check_contains "the table records which changelog source won" "changelog | core | ok (docs)" "$OUT"
check_contains "the canary passes when the changelog is as new as npm latest" "changelog-canary | core | ok" "$OUT"
check_contains "the table ends with a reconciliation line" "summary:" "$OUT"
TXT="$(cat "$FCACHE/support-release-notes.txt")"
check_contains "HTML is rendered to searchable text" "Launching Salesforce in Claude (beta)" "$TXT"
check_contains "entities are decoded in the rendering" "sales skills & more" "$TXT"
check_absent "markup does not survive the rendering" "<h3" "$TXT"
check_absent "script bodies do not survive the rendering" "not content" "$TXT"

# Digest caching: the newest two are always re-fetched; older cached digests are left alone.
printf 'CHANGED upstream\n' > "$SRC/whats-new/2026-w30.md"
printf 'CHANGED upstream\n' > "$SRC/whats-new/2026-w37.md"
OUT=$(fetch_env bash "$HELPER" fetch 2>/dev/null)
check_contains "an older cached digest is not re-fetched" "digest 2026-w30 | core | cached" "$OUT"
check_contains "an older cached digest keeps its content" "original digest body" "$(cat "$FCACHE/digests/2026-w30.md")"
check_contains "a recent digest is refreshed" "CHANGED upstream" "$(cat "$FCACHE/digests/2026-w37.md")"

# Permanent failure: reported, not retried, and a good cached copy is never clobbered.
OUT=$(fetch_env "NEW_FUNCTIONALITY_CHECK_URL_BEST_PRACTICES=$(file_url "$SRC/missing.md")" bash "$HELPER" fetch 2>"$TMPDIR_T/perm.err"); RC=$?
check "a failed extended source makes fetch exit 2" "2" "$RC"
check_contains "the table marks the failed source" "best-practices | extended | FAILED" "$OUT"
check_contains "the failure is classified" "permanent" "$OUT"
check_absent "a permanent failure is never retried" "attempt 1/2" "$(cat "$TMPDIR_T/perm.err")"
check_contains "the good cached copy survives a failed fetch" "Verify your work." "$(cat "$FCACHE/best-practices.md")"
check_contains "the other sources still succeed" "docs-index | extended | ok" "$OUT"

# Transient failure: bounded retries with a WARN per attempt, then a loud core failure.
OUT=$(fetch_env "NEW_FUNCTIONALITY_CHECK_URL_INDEX=http://127.0.0.1:9/whats-new.md" bash "$HELPER" fetch 2>"$TMPDIR_T/trans.err"); RC=$?
check "a failed core source makes fetch exit 2" "2" "$RC"
check_contains "a transient failure logs each retry" "attempt 1/2" "$(cat "$TMPDIR_T/trans.err")"
check_contains "the table marks the core failure" "whats-new-index | core | FAILED" "$OUT"
check_contains "exhausted retries are classified" "transient" "$OUT"

# Changelog fallback chain: docs -> mirror -> local cache (STALE) -> FAILED.
OUT=$(fetch_env "NEW_FUNCTIONALITY_CHECK_URL_CHANGELOG=$(file_url "$SRC/nope.md")" bash "$HELPER" fetch 2>/dev/null); RC=$?
check_contains "the mirror is used when the docs changelog fails" "changelog | core | ok (mirror)" "$OUT"
check "falling back to the mirror is still a clean run" "0" "$RC"
printf '# Changelog\n\n### v9 renamed headings\n- Added x\n' > "$SRC/changelog-drifted.md"
OUT=$(fetch_env "NEW_FUNCTIONALITY_CHECK_URL_CHANGELOG=$(file_url "$SRC/changelog-drifted.md")" bash "$HELPER" fetch 2>/dev/null)
check_contains "a changelog that fetches but does not PARSE also falls back" "changelog | core | ok (mirror)" "$OUT"
OUT=$(fetch_env "NEW_FUNCTIONALITY_CHECK_URL_CHANGELOG=$(file_url "$SRC/nope.md")" "NEW_FUNCTIONALITY_CHECK_URL_CHANGELOG_MIRROR=$(file_url "$SRC/nope2.md")" bash "$HELPER" fetch 2>/dev/null); RC=$?
check_contains "the local cache is the last resort and is flagged" "changelog | core | STALE" "$OUT"
check "a stale changelog is never a clean run" "2" "$RC"
OUT=$(fetch_env "NEW_FUNCTIONALITY_CHECK_URL_CHANGELOG=$(file_url "$SRC/nope.md")" "NEW_FUNCTIONALITY_CHECK_URL_CHANGELOG_MIRROR=$(file_url "$SRC/nope2.md")" "NEW_FUNCTIONALITY_CHECK_LOCAL_CHANGELOG=$SRC/nope3.md" bash "$HELPER" fetch 2>/dev/null)
check_contains "with every changelog source gone the core failure is loud" "changelog | core | FAILED" "$OUT"

# Canary: a changelog that parses but trails npm latest is partial format drift, not "nothing new".
printf '{"name":"@anthropic-ai/claude-code","version":"2.1.290"}\n' > "$SRC/npm-newer.json"
OUT=$(fetch_env "NEW_FUNCTIONALITY_CHECK_URL_NPM_LATEST=$(file_url "$SRC/npm-newer.json")" bash "$HELPER" fetch 2>/dev/null); RC=$?
check_contains "a changelog trailing npm latest trips the canary" "changelog-canary | core | DEGRADED" "$OUT"
check "a tripped canary is never a clean run" "2" "$RC"

# Index format drift is a parse error (exit 3), and it is a core failure.
printf '# What is new\n<Release name="Week 37">renamed</Release>\n' > "$SRC/index-drifted.md"
OUT=$(fetch_env "NEW_FUNCTIONALITY_CHECK_URL_INDEX=$(file_url "$SRC/index-drifted.md")" bash "$HELPER" fetch 2>/dev/null); RC=$?
check "an index that fetches but does not parse exits 3" "3" "$RC"
check_contains "the table says it was a parse error" "whats-new-index | core | FAILED | parse error" "$OUT"

# Overall deadline: nothing hangs past it, and the table still prints (ACCOUNT duty).
OUT=$(fetch_env NEW_FUNCTIONALITY_CHECK_DEADLINE_SECS=0 bash "$HELPER" fetch 2>/dev/null); RC=$?
check "an exhausted deadline is never a clean run" "2" "$RC"
check_contains "sources skipped by the deadline are listed" "deadline" "$OUT"
check_contains "the reconciliation line still prints" "summary:" "$OUT"

# Production default is https-only: without the test override a file:// URL is refused.
# (Every URL still points at a fixture, so even this case never touches the network.)
OUT=$(fetch_env "NEW_FUNCTIONALITY_CHECK_CACHE_DIR=$TMPDIR_T/https-only" "NEW_FUNCTIONALITY_CHECK_CURL_PROTO==https" bash "$HELPER" fetch 2>/dev/null)
check_contains "non-https URLs are refused by default" "whats-new-index | core | FAILED" "$OUT"

# Host allowlist (pure check): a redirect may only land on an official host.
hosts() { h bash "$HELPER" _host-allowed "$1" >/dev/null 2>&1; echo $?; }
check "code.claude.com is allowed"               "0" "$(hosts https://code.claude.com/docs/en/whats-new.md)"
check "raw.githubusercontent.com is allowed"     "0" "$(hosts https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md)"
check "an unknown host is refused"               "1" "$(hosts https://evil.example/whats-new.md)"
check "a look-alike suffix host is refused"      "1" "$(hosts https://code.claude.com.evil.example/x)"
check "a look-alike prefix host is refused"      "1" "$(hosts https://evilcode.claude.com.example/x)"
check "userinfo tricks are refused"              "1" "$(hosts https://code.claude.com@evil.invalid/x)"

# ---------------------------------------------------------------------------
# Watched pages: watch-diff is READ-ONLY; watch-commit promotes snapshots at Capture,
# so a sweep that dies between the two can never lose a diff.
# ---------------------------------------------------------------------------
WCACHE="$TMPDIR_T/watch-cache"; WLEDGER="$TMPDIR_T/watch-ledger"
mkdir -p "$WCACHE" "$WLEDGER"
printf '# Docs\n\n- [Hooks](https://x/hooks.md): hooks\n- [Skills](https://x/skills.md): skills\n' > "$WCACHE/llms.txt"
printf '# Best practices\n\nVerify your work.\nPlan first.\n' > "$WCACHE/best-practices.md"
printf '{"plugins":[{"name":"superpowers","version":"6.3.0"},{"name":"claude-code-setup","version":"1"}]}\n' > "$WCACHE/marketplace.json"
w() {
    h "NEW_FUNCTIONALITY_CHECK_CACHE_DIR=$WCACHE" "CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$WLEDGER" \
      NEW_FUNCTIONALITY_CHECK_FLOOR_DOCS_INDEX=1 NEW_FUNCTIONALITY_CHECK_FLOOR_BEST_PRACTICES=1 NEW_FUNCTIONALITY_CHECK_FLOOR_MARKETPLACE=1 "$@"
}

OUT=$(w bash "$HELPER" watch-diff); RC=$?
check "first sight exits 0" "0" "$RC"
check_contains "first sight is reported as a baseline, not as 'no change'" "docs-index: baseline" "$OUT"
check_contains "a baseline says earlier changes were not diffed" "not diffed" "$OUT"
if [ -f "$WLEDGER/snapshots/docs-index.txt" ]; then check "watch-diff never promotes a snapshot" "absent" "present"; else check "watch-diff never promotes a snapshot" "absent" "absent"; fi

OUT=$(w bash "$HELPER" watch-commit)
check_contains "watch-commit promotes the pending snapshots" "docs-index" "$OUT"
if [ -f "$WLEDGER/snapshots/docs-index.txt" ]; then check "the snapshot exists after commit" "present" "present"; else check "the snapshot exists after commit" "present" "absent"; fi

OUT=$(w bash "$HELPER" watch-diff)
check_contains "an unchanged page reports no change" "docs-index: unchanged" "$OUT"

printf '# Docs\n\n- [Hooks](https://x/hooks.md): hooks\n- [Plugin evals](https://x/plugin-evals.md): new page\n' > "$WCACHE/llms.txt"
printf '{"plugins":[{"name":"superpowers","version":"6.4.0"},{"name":"claude-code-setup","version":"1"},{"name":"claude-security","version":"1"}]}\n' > "$WCACHE/marketplace.json"
OUT=$(w bash "$HELPER" watch-diff)
check_contains "a new docs page shows as an added line" "+ - [Plugin evals](https://x/plugin-evals.md): new page" "$OUT"
check_contains "a removed docs page shows as a removed line" "- - [Skills](https://x/skills.md): skills" "$OUT"
check_contains "a new marketplace plugin shows by NAME" "+ claude-security" "$OUT"
check_absent "a version bump alone is not marketplace churn" "6.4.0" "$OUT"
OUT2=$(w bash "$HELPER" watch-diff)
check "an uncommitted diff is reported again (nothing is lost if the sweep dies)" "$OUT" "$OUT2"
w bash "$HELPER" watch-commit >/dev/null
OUT=$(w bash "$HELPER" watch-diff)
check_contains "after commit the same page is unchanged" "docs-index: unchanged" "$OUT"

# Sanity floors: an error page or a gutted file is never accepted as the new truth.
OUT=$(w NEW_FUNCTIONALITY_CHECK_FLOOR_DOCS_INDEX=50 bash "$HELPER" watch-diff); RC=$?
check "a page below its sanity floor makes watch-diff exit 2" "2" "$RC"
check_contains "the refusal names the floor" "docs-index: REFUSED" "$OUT"
printf 'x\n' > "$WCACHE/best-practices.md"
i=0; : > "$WLEDGER/snapshots/best-practices.txt"; while [ $i -lt 40 ]; do echo "line $i" >> "$WLEDGER/snapshots/best-practices.txt"; i=$((i+1)); done
OUT=$(w bash "$HELPER" watch-diff); RC=$?
check_contains "a page that shrank by more than half is refused" "best-practices: REFUSED" "$OUT"
printf 'not json at all\n' > "$WCACHE/marketplace.json"
OUT=$(w bash "$HELPER" watch-diff 2>&1); RC=$?
check_contains "a marketplace manifest that is not JSON is refused" "marketplace: REFUSED" "$OUT"
rm -f "$WCACHE/llms.txt"
OUT=$(w bash "$HELPER" watch-diff 2>&1); RC=$?
check_contains "a page that was not fetched is reported, not skipped silently" "docs-index: SKIPPED" "$OUT"
check "an unfetched page makes watch-diff exit 2" "2" "$RC"
OUT=$(h "NEW_FUNCTIONALITY_CHECK_CACHE_DIR=$WCACHE" "CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$TMPDIR_T/empty-ledger" bash "$HELPER" watch-commit)
check_contains "watch-commit with nothing pending says so" "nothing pending" "$OUT"

# ---------------------------------------------------------------------------
# Upstream issues this config works around: an explicit table, never a heuristic scan
# (the config is full of client ticket numbers that are not upstream issues).
# ---------------------------------------------------------------------------
TRACKED="$TMPDIR_T/tracked-issues.md"
printf '# Tracked upstream issues\n\n| issue | keywords | local workaround |\n|---|---|---|\n| 45645 | worktreeConfig, repositoryformatversion | hooks/worktree-config-cleanup.sh |\r\n| 31391 | statusline | statusline.sh |\n| not-a-number | x | y |\n' > "$TRACKED"
OUT=$(h bash "$HELPER" tracked-issues --file "$TRACKED")
check "tracked-issues lists only well-formed rows" "2" "$(printf '%s\n' "$OUT" | grep -c .)"
check_contains "a row carries issue, keywords, workaround" "45645|worktreeConfig, repositoryformatversion|hooks/worktree-config-cleanup.sh" "$OUT"
check_absent "carriage returns from a Windows-edited table are stripped" "$(printf '\r')" "$OUT"
h bash "$HELPER" tracked-issues --file "$TMPDIR_T/nope.md" >/dev/null 2>&1
check "a missing tracked-issues table is a precondition error" "1" "$?"
# The issues a config works around are per-machine: a tracked-issues.md beside the ledger wins
# over the template the skill ships, and the issue commands read the same file.
TI_LEDGER="$TMPDIR_T/ti-ledger"; mkdir -p "$TI_LEDGER"
printf '| issue | keywords | local workaround |\n|---|---|---|\n| 11111 | somekey | a local workaround |\n' > "$TI_LEDGER/tracked-issues.md"
OUT=$(h "CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$TI_LEDGER" bash "$HELPER" tracked-issues)
check_contains "the ledger's own tracked-issues.md is preferred over the shipped template" "11111|somekey|a local workaround" "$OUT"
TI_EMPTY="$TMPDIR_T/ti-empty"; mkdir -p "$TI_EMPTY"
h "CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$TI_EMPTY" bash "$HELPER" tracked-issues >/dev/null 2>&1
check "without a per-machine table the shipped template is read" "0" "$?"

mkdir -p "$SRC/issues"
printf '{"number":45645,"title":"Worktree cleanup leaves stale git config","user":{"login":"x"},"state":"closed","state_reason":"duplicate","milestone":{"state":"open"},"closed_at":"2026-04-12T09:18:49Z"}\n' > "$SRC/issues/45645"
printf '{"number":31391,"title":"Statusline flicker","state":"open","state_reason":null,"closed_at":null}\n' > "$SRC/issues/31391"
printf '{"message":"API rate limit exceeded for 1.2.3.4.","documentation_url":"https://docs.github.com"}\n' > "$SRC/issues/99999"
iss() { h "NEW_FUNCTIONALITY_CHECK_CACHE_DIR=$TMPDIR_T/issue-cache" "NEW_FUNCTIONALITY_CHECK_CURL_PROTO==https,http,file" "NEW_FUNCTIONALITY_CHECK_URL_ISSUE_API_BASE=$(file_url "$SRC/issues")" "$@"; }
OUT=$(iss bash "$HELPER" issue-status 45645); RC=$?
check "issue-status exits 0 for a readable issue" "0" "$RC"
check_contains "issue-status reports state and reason" "#45645 | closed | duplicate | 2026-04-12T09:18:49Z" "$OUT"
check_contains "issue-status reports the title" "Worktree cleanup leaves stale git config" "$OUT"
OUT=$(iss bash "$HELPER" issue-status 31391)
check_contains "an open issue reads as open (a nested milestone.state must not confuse it)" "#31391 | open | - | -" "$OUT"
OUT=$(iss bash "$HELPER" issue-status 99999 2>&1); RC=$?
check "an API error is surfaced, never a masking default" "2" "$RC"
check_contains "the API's own message is shown" "rate limit" "$OUT"
iss bash "$HELPER" issue-status 45645x >/dev/null 2>&1
check "a non-numeric issue is a usage error" "1" "$?"
OUT=$(iss NEW_FUNCTIONALITY_CHECK_JSON_TOOL=python bash "$HELPER" issue-status 45645)
check_contains "the python JSON path gives the same answer as jq" "#45645 | closed | duplicate" "$OUT"

# issue-evidence greps the FULL changelog — Fixed bullets included — for a tracked issue's keywords.
cat > "$TMPDIR_T/changelog-evidence.md" <<'EV'
# Changelog

## 2.1.239

- Fixed the Linux sandbox making a nonexistent `.git/config.worktree` unreadable in repos with `extensions.worktreeConfig` set

## 2.1.207

- Fixed `extensions.worktreeConfig` being left in the repo's `.git/config` after the last worktree was removed
- Added an unrelated thing

## 2.1.100

- Added nothing relevant
EV
OUT=$(h bash "$HELPER" issue-evidence 45645 --tracked "$TRACKED" --file "$TMPDIR_T/changelog-evidence.md")
check_contains "evidence names the version that mentions the keyword" "## 2.1.207" "$OUT"
check_contains "evidence includes Fixed bullets (the backfill slices drop them)" "Fixed \`extensions.worktreeConfig\` being left" "$OUT"
check_absent "evidence excludes unrelated bullets" "unrelated thing" "$OUT"
check_absent "evidence excludes versions with no match" "2.1.100" "$OUT"
OUT=$(h bash "$HELPER" issue-evidence 31391 --tracked "$TRACKED" --file "$TMPDIR_T/changelog-evidence.md"); RC=$?
check "no evidence prints nothing" "" "$OUT"
check "no evidence is still exit 0 (absence is an answer)" "0" "$RC"
h bash "$HELPER" issue-evidence 77777 --tracked "$TRACKED" --file "$TMPDIR_T/changelog-evidence.md" >/dev/null 2>&1
check "an untracked issue is a usage error" "1" "$?"

# ---------------------------------------------------------------------------
# Deterministic verification: "verified" is a fact the helper checks, not an agent's claim.
# ---------------------------------------------------------------------------
printf 'Set `maxEffortLevel` at the top level or per model\nunder `modelSettings` to cap the effort level on every provider.\n' > "$TMPDIR_T/quote-source.md"
h bash "$HELPER" verify-quote "$TMPDIR_T/quote-source.md" 'Set `maxEffortLevel` at the top level or per model under `modelSettings`' >/dev/null
check "a quote that spans a line break is found (whitespace-normalized)" "0" "$?"
h bash "$HELPER" verify-quote "$TMPDIR_T/quote-source.md" 'Set `maxEffortLevel` to uncap the effort level' >/dev/null 2>&1
check "a paraphrase is NOT a quote" "1" "$?"
h bash "$HELPER" verify-quote "$TMPDIR_T/quote-source.md" 'effort' >/dev/null 2>&1
check "a trivially short quote is refused" "1" "$?"
h bash "$HELPER" verify-quote "$TMPDIR_T/nope.md" 'Set `maxEffortLevel` at the top level' >/dev/null 2>&1
check "a missing source file cannot verify anything" "1" "$?"

lead() { h "NEW_FUNCTIONALITY_CHECK_CACHE_DIR=$TMPDIR_T/lead-cache" "$@"; }
OUT=$(lead bash "$HELPER" verify-lead "https://evil.example/post" "Set maxEffortLevel at the top level" 2>&1); RC=$?
check "a lead on a non-official host is refused without any fetch" "1" "$RC"
check_contains "the refusal says why" "not an official host" "$OUT"
OUT=$(lead bash "$HELPER" verify-lead "http://code.claude.com/docs/en/x" "Set maxEffortLevel at the top level" 2>&1); RC=$?
check "a non-https lead is refused" "1" "$RC"
printf '<html><body><article><p>Set <code>maxEffortLevel</code> at the top level to cap effort.</p></article></body></html>\n' > "$SRC/official-page.html"
OUT=$(lead "NEW_FUNCTIONALITY_CHECK_CURL_PROTO==https,http,file" NEW_FUNCTIONALITY_CHECK_VERIFY_ANY_HOST=1 bash "$HELPER" verify-lead "$(file_url "$SRC/official-page.html")" "Set maxEffortLevel at the top level to cap effort" 2>&1); RC=$?
check "a quote present in the fetched official page verifies (HTML is rendered first)" "0" "$RC"
OUT=$(lead "NEW_FUNCTIONALITY_CHECK_CURL_PROTO==https,http,file" NEW_FUNCTIONALITY_CHECK_VERIFY_ANY_HOST=1 bash "$HELPER" verify-lead "$(file_url "$SRC/official-page.html")" "maxEffortLevel removes every limit forever" 2>&1); RC=$?
check "a quote absent from the fetched page does not verify" "1" "$RC"
OUT=$(lead "NEW_FUNCTIONALITY_CHECK_CURL_PROTO==https,http,file" NEW_FUNCTIONALITY_CHECK_VERIFY_ANY_HOST=1 "NEW_FUNCTIONALITY_CHECK_RETRY_ATTEMPTS=1" bash "$HELPER" verify-lead "$(file_url "$SRC/no-such-page.html")" "Set maxEffortLevel at the top level to cap effort" 2>&1); RC=$?
check "a page that cannot be fetched is a fetch failure, not a 'no'" "2" "$RC"

# ---------------------------------------------------------------------------
# Outbound privacy: a research agenda is scrubbed BEFORE it leaves the machine.
# ---------------------------------------------------------------------------
SCRUB_LEDGER="$TMPDIR_T/scrub-ledger"; mkdir -p "$SCRUB_LEDGER"
printf '# one term per line\nGlobex\nInitech\n\n' > "$SCRUB_LEDGER/denylist.txt"
s() { h "CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$SCRUB_LEDGER" "NEW_FUNCTIONALITY_CHECK_SCRUB_USER=exampleuser" "NEW_FUNCTIONALITY_CHECK_SCRUB_HOME=/Users/exampleuser" "NEW_FUNCTIONALITY_CHECK_SCRUB_HOST=example-host" "$@"; }
printf 'Claude Code hooks: how do "if" conditions behave on compound Bash commands?\nsubagent omitClaudeMd real-world usage\n' > "$TMPDIR_T/agenda-clean.txt"
s bash "$HELPER" scrub-check "$TMPDIR_T/agenda-clean.txt" >/dev/null
check "a clean agenda passes" "0" "$?"
printf 'hook pitfalls for the globex client repo\n' > "$TMPDIR_T/agenda-client.txt"
OUT=$(s bash "$HELPER" scrub-check "$TMPDIR_T/agenda-client.txt" 2>&1); RC=$?
check "a client name blocks the dispatch (case-insensitive)" "1" "$RC"
check_contains "the hit names its line" "line 1" "$OUT"
printf 'see /Users/exampleuser/.claude/hooks/scan-secrets.sh\n' > "$TMPDIR_T/agenda-path.txt"
s bash "$HELPER" scrub-check "$TMPDIR_T/agenda-path.txt" >/dev/null 2>&1
check "a home path blocks the dispatch" "1" "$?"
printf 'settings on example-host\n' > "$TMPDIR_T/agenda-host.txt"
s bash "$HELPER" scrub-check "$TMPDIR_T/agenda-host.txt" >/dev/null 2>&1
check "the hostname blocks the dispatch" "1" "$?"
s bash "$HELPER" scrub-check "$TMPDIR_T/no-agenda.txt" >/dev/null 2>&1
check "a missing agenda file is an error, never a pass" "1" "$?"

# ---------------------------------------------------------------------------
# validate-candidates: agent output is DATA — strict JSON, whitelisted fields, capped lengths.
# ---------------------------------------------------------------------------
cat > "$TMPDIR_T/eval-good.json" <<'JSON'
{"header": {"slice": "digests 2026-w36..w37", "items_reviewed": 31, "omitted_count": 0},
 "candidates": [
  {"verdict": "PROPOSE", "title": "Set omitClaudeMd on the review specialists", "feature_key": "agent.omitClaudeMd",
   "target_type": "agent", "target_paths": ["~/.claude/agents/code-reviewer-security.md"],
   "upstream": {"source": "changelog", "ref": "2.1.271", "version": "2.1.271",
                "url": "https://code.claude.com/docs/en/changelog#2-1-271", "docs_url": "https://code.claude.com/docs/en/sub-agents",
                "quote": "Added omitClaudeMd to agent frontmatter and --agents JSON"},
   "today": "Every subagent loads the 62 KB global CLAUDE.md.", "proposed_change": "Add omitClaudeMd: true to the five specialists.",
   "benefit": "H", "effort": "S", "risk": "low", "sensitive": false, "verify_before_adopting": "Confirm the key on the installed CLI."},
  {"verdict": "NO-ACTION", "title": "Pop Desktop panes out", "feature_key": "desktop.pop-out-panes", "target_type": "other",
   "upstream": {"source": "whats-new", "ref": "2026-w37", "url": "https://code.claude.com/docs/en/whats-new/2026-w37",
                "quote": "you can pop any pane out into its own window"},
   "reason_if_no_action": "Desktop-only"}
 ]}
JSON
OUT=$(h bash "$HELPER" validate-candidates evaluator "$TMPDIR_T/eval-good.json"); RC=$?
check "a well-formed evaluator file validates" "0" "$RC"
check_contains "validation reports the counts" "1 PROPOSE" "$OUT"

bad() { # bad <name> <python-expression mutating doc> -> writes $TMPDIR_T/eval-bad.json
    python3 - "$TMPDIR_T/eval-good.json" "$TMPDIR_T/eval-bad.json" "$2" <<'MUTATE'
import json, sys
doc = json.load(open(sys.argv[1]))
exec(sys.argv[3])
json.dump(doc, open(sys.argv[2], "w"))
MUTATE
    OUT=$(h bash "$HELPER" validate-candidates evaluator "$TMPDIR_T/eval-bad.json" 2>&1); RC=$?
    check "rejected: $1" "1" "$RC"
}
bad "an unknown field (whitelist, not blacklist)"   'doc["candidates"][0]["run_this"] = "rm -rf ~"'
bad "an unknown verdict"                            'doc["candidates"][0]["verdict"] = "APPLY-NOW"'
bad "an over-long proposed_change"                  'doc["candidates"][0]["proposed_change"] = "x" * 5000'
bad "a control character inside a string"           'doc["candidates"][0]["title"] = "ok\x1b[2J hidden"'
bad "a non-https upstream url"                      'doc["candidates"][0]["upstream"]["url"] = "http://code.claude.com/x"'
bad "an upstream url on a non-official host"        'doc["candidates"][0]["upstream"]["url"] = "https://evil.example/x"'
bad "a PROPOSE without a quote"                     'doc["candidates"][0]["upstream"]["quote"] = ""'
bad "a PROPOSE without the sensitive flag"          'del doc["candidates"][0]["sensitive"]'
bad "a NO-ACTION without a reason"                  'del doc["candidates"][1]["reason_if_no_action"]'
bad "a header without omitted_count (silent truncation)" 'del doc["header"]["omitted_count"]'
bad "more candidates than the per-dispatch cap"     'doc["candidates"] = doc["candidates"] * 30'
printf 'Here is the JSON you asked for:\n{"header":{}}\n' > "$TMPDIR_T/eval-prose.json"
h bash "$HELPER" validate-candidates evaluator "$TMPDIR_T/eval-prose.json" >/dev/null 2>&1
check "rejected: prose around the JSON (strict parse)" "1" "$?"

cat > "$TMPDIR_T/research-good.json" <<'JSON'
{"header": {"lanes_completed": ["hooks & automation"], "budget_used": {"searches": 6, "fetches": 5},
            "fetch_failures": [{"url": "https://example.org/x", "reason": "timeout after 2 retries"}]},
 "leads": [
  {"title": "if-conditions do not match compound commands", "feature_key": "hooks.if", "target_type": "hook",
   "source_tier": "community", "url": "https://blog.example.org/claude-hooks", "quote": "the if rule only sees the first command in a chain",
   "claim": "An if condition may miss `cd x && git commit`.", "benefit": "M", "effort": "S", "risk": "low", "sensitive": false,
   "verification": {"status": "unverified", "by_url": "", "by_quote": ""}}
 ]}
JSON
OUT=$(h bash "$HELPER" validate-candidates researcher "$TMPDIR_T/research-good.json"); RC=$?
check "a well-formed researcher file validates" "0" "$RC"
python3 - "$TMPDIR_T/research-good.json" "$TMPDIR_T/research-bad.json" <<'MUTATE'
import json, sys
doc = json.load(open(sys.argv[1]))
doc["leads"][0]["verification"] = {"status": "verified", "by_url": "https://blog.example.org/claude-hooks", "by_quote": "the if rule only sees the first command in a chain"}
json.dump(doc, open(sys.argv[2], "w"))
MUTATE
h bash "$HELPER" validate-candidates researcher "$TMPDIR_T/research-bad.json" >/dev/null 2>&1
check "rejected: a lead 'verified' against a non-official host" "1" "$?"
h bash "$HELPER" validate-candidates reviewer "$TMPDIR_T/eval-good.json" >/dev/null 2>&1
check "an unknown kind is a usage error" "1" "$?"

# ---------------------------------------------------------------------------
# inventory: what the config ACTUALLY contains — and never a secret.
# ---------------------------------------------------------------------------
mkdir -p "$FAKE_CLAUDE/hooks" "$FAKE_CLAUDE/agents" "$FAKE_CLAUDE/skills/alpha/resources" "$FAKE_CLAUDE/skills/beta"
cat > "$FAKE_CLAUDE/settings.json" <<'JSON'
{"env": {"CLAUDE_CODE_REVIEW_ON_STOP": "0", "SOME_FLAG": "true", "DR_SYNC_DEBOUNCE_SECS": "86400", "API_TOKEN": "fixture-value-NOTREAL-4471"},
 "permissions": {"defaultMode": "auto", "allow": ["Bash(ls:*)", "Bash(jq:*)"], "deny": ["Read(**/.env)"]},
 "model": "fable",
 "hooks": {"UserPromptSubmit": [{"hooks": [{"type": "command", "command": "bash ~/.claude/hooks/wired.sh", "statusMessage": "x"}]}],
           "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/gate.sh", "if": "Bash(git *)", "async": true}]}],
           "PostToolUse": [{"matcher": "Write", "hooks": [{"type": "command", "command": "bash", "args": ["/opt/anywhere/.claude/hooks/execform.sh", "--flag"], "timeout": 5}]}]},
 "enabledPlugins": {"superpowers@claude-plugins-official": true, "off@claude-plugins-official": false}}
JSON
printf '#!/bin/bash\n' > "$FAKE_CLAUDE/hooks/wired.sh"; printf '#!/bin/bash\n' > "$FAKE_CLAUDE/hooks/gate.sh"; printf '#!/bin/bash\n' > "$FAKE_CLAUDE/hooks/orphan.sh"
printf '#!/bin/bash\n' > "$FAKE_CLAUDE/hooks/execform.sh"
printf -- '---\nname: reviewer\ndescription: reviews\ntools: Read, Grep\nmodel: sonnet\nomitClaudeMd: true\n---\n\nbody\n' > "$FAKE_CLAUDE/agents/reviewer.md"
printf -- '---\nname: alpha\ndescription: Use when alpha\n---\n\n# Alpha\n' > "$FAKE_CLAUDE/skills/alpha/SKILL.md"
printf '#!/bin/bash\n' > "$FAKE_CLAUDE/skills/alpha/helper.sh"
printf '# Skill: Beta\n\nno frontmatter here\n' > "$FAKE_CLAUDE/skills/beta/SKILL.md"
printf '# Global\n\nrules\n\n%s\n' '@RTK.md' > "$FAKE_CLAUDE/CLAUDE.md"
printf '{"version_from":"2.1.274","version_to":"2.1.278"}\n' > "$FAKE_CLAUDE/.last-update-result.json"

for TOOL in jq python; do
    if [ "$TOOL" = "jq" ] && ! command -v jq >/dev/null 2>&1; then
        echo "SKIP-LOUD: jq is not installed on this machine — the jq branch of inventory is NOT covered here (the python branch still is)"
        continue
    fi
    OUT=$(h "NEW_FUNCTIONALITY_CHECK_JSON_TOOL=$TOOL" bash "$HELPER" inventory); RC=$?
    check "[$TOOL] inventory exits 0" "0" "$RC"
    check_contains "[$TOOL] a wired hook is listed with its event" "UserPromptSubmit | * | bash ~/.claude/hooks/wired.sh | -" "$OUT"
    check_contains "[$TOOL] modern hook fields are surfaced" "PreToolUse | Bash | bash ~/.claude/hooks/gate.sh | if,async" "$OUT"
    UNWIRED="$(printf '%s\n' "$OUT" | awk '/^### Hook files on disk/ { inside = 1; next } /^###/ { inside = 0 } inside')"
    check_contains "[$TOOL] an unwired hook file is called out" "orphan.sh" "$UNWIRED"
    # Exec form (`command` + `args`) keeps the script path in args — the report must still show it,
    # or an exec-form hook looks like a file that nothing runs.
    check_contains "[$TOOL] an exec-form hook is listed with its arguments" "PostToolUse | Write | bash /opt/anywhere/.claude/hooks/execform.sh --flag | args,timeout" "$OUT"
    check_absent   "[$TOOL] an exec-form hook's script is not reported as unwired" "execform.sh" "$UNWIRED"
    check_contains "[$TOOL] an agent shows model, tools, extra keys" "reviewer | sonnet | Read, Grep | omitClaudeMd" "$OUT"
    check_contains "[$TOOL] a skill shows its frontmatter keys" "alpha | frontmatter: name,description" "$OUT"
    check_contains "[$TOOL] a skill shows resources and helpers" "resources: yes | helpers: helper.sh" "$OUT"
    check_contains "[$TOOL] a frontmatter-less skill is flagged" "beta | frontmatter: none" "$OUT"
    check_contains "[$TOOL] a 0/1 env value is shown (evaluators need it)" "CLAUDE_CODE_REVIEW_ON_STOP=0" "$OUT"
    check_contains "[$TOOL] a boolean env value is shown" "SOME_FLAG=true" "$OUT"
    check_contains "[$TOOL] any other numeric env value is masked (IDs and PINs are numeric too)" "DR_SYNC_DEBOUNCE_SECS=<set>" "$OUT"
    check_absent   "[$TOOL] a secret env value NEVER appears" "NOTREAL-4471" "$OUT"
    check_contains "[$TOOL] permissions are summarized as counts" "defaultMode=auto allow=2 deny=1 ask=0" "$OUT"
    check_contains "[$TOOL] only enabled plugins are listed" "superpowers@claude-plugins-official" "$OUT"
    check_absent   "[$TOOL] a disabled plugin is not listed as enabled" "off@claude-plugins-official" "$OUT"
    check_contains "[$TOOL] CLAUDE.md imports are listed" "@RTK.md" "$OUT"
    check_contains "[$TOOL] unused feature surfaces are listed" "rules/" "$OUT"
    check_contains "[$TOOL] the installed CLI version is reported" "2.1.278" "$OUT"
done

# ---------------------------------------------------------------------------
# Ledger bookkeeping: next-id, snapshot, ledger-check, lock
# ---------------------------------------------------------------------------
LB="$TMPDIR_T/book-ledger"; mkdir -p "$LB"
b() { h "CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$LB" "$@"; }
check "next-id on an empty ledger" "RW-0001" "$(b bash "$HELPER" next-id)"
cat > "$LB/ledger.md" <<'LEDGER'
# New-Functionality Check Ledger

## Proposal index

| ID | status | target | feature_key | title | upstream | logged | decided |
|---|---|---|---|---|---|---|---|
| RW-0001 | proposed | hook | hooks.first | first | 2026-w13 | 2026-09-19 | |
| RW-0002 | declined — not worth it | skill | skills.second | second | 2.1.129 | 2026-09-19 | 2026-09-20 |
LEDGER
printf '### RW-0001 · hooks · first\n\nbody\n\n### RW-0002 · skills · second\n\nbody\n' > "$LB/proposals.md"
check "next-id continues after the highest id" "RW-0003" "$(b bash "$HELPER" next-id)"
OUT=$(b bash "$HELPER" ledger-check); RC=$?
check "a consistent ledger passes ledger-check" "0" "$RC"
check_contains "ledger-check reports the count" "2 proposals" "$OUT"

OUT=$(b bash "$HELPER" snapshot); RC=$?
check "snapshot exits 0" "0" "$RC"
SNAPDIR="$(printf '%s\n' "$OUT" | sed -n 's/^snapshot: //p')"
if [ -f "$SNAPDIR/ledger.md" ] && [ -f "$SNAPDIR/proposals.md" ]; then check "snapshot copied the ledger files" "yes" "yes"; else check "snapshot copied the ledger files" "yes" "no ($SNAPDIR)"; fi

printf '| RW-0002 | proposed | skill | skills.reused | reused id | x | 2026-09-21 | |\n' >> "$LB/ledger.md"
b bash "$HELPER" ledger-check >/dev/null 2>&1
check "ledger-check rejects a duplicate id" "1" "$?"
python3 - "$LB/ledger.md" <<'FIXUP'
import sys
p = sys.argv[1]; s = open(p).read().replace("| RW-0002 | proposed | skill | skills.reused | reused id | x | 2026-09-21 | |\n", "| RW-0003 | maybe-later | skill | skills.third | third | x | 2026-09-21 | |\n"); open(p, "w").write(s)
FIXUP
printf '\n### RW-0003 · skills · third\n\nbody\n' >> "$LB/proposals.md"
OUT=$(b bash "$HELPER" ledger-check 2>&1); RC=$?
check "ledger-check rejects a status outside the vocabulary" "1" "$RC"
check_contains "the bad status is named" "maybe-later" "$OUT"
python3 - "$LB/ledger.md" <<'FIXUP'
import sys
p = sys.argv[1]; s = open(p).read().replace("| RW-0003 | maybe-later |", "| RW-0003 | proposed |"); open(p, "w").write(s)
FIXUP
printf '### RW-0001 · hooks · first\n\nbody\n' > "$LB/proposals.md"
OUT=$(b bash "$HELPER" ledger-check 2>&1); RC=$?
check "ledger-check rejects an index row with no detail block" "1" "$RC"
printf '### RW-0001 · hooks · first\n\nbody\n\n### RW-0002 · skills · second\n\nbody\n\n### RW-0003 · skills · third\n\nbody\n' > "$LB/proposals.md"
python3 - "$LB/ledger.md" <<'FIXUP'
import sys
p = sys.argv[1]; s = open(p).read().replace("| RW-0001 | proposed | hook | hooks.first | first | 2026-w13 | 2026-09-19 | |\n", ""); open(p, "w").write(s)
FIXUP
OUT=$(b bash "$HELPER" ledger-check 2>&1); RC=$?
check "ledger-check rejects a row that vanished since the last snapshot (never delete)" "1" "$RC"

b bash "$HELPER" lock >/dev/null 2>&1;  check "the first lock succeeds" "0" "$?"
b bash "$HELPER" lock >/dev/null 2>&1;  check "a second concurrent lock is refused" "1" "$?"
b bash "$HELPER" unlock >/dev/null 2>&1; check "unlock succeeds" "0" "$?"
b bash "$HELPER" lock >/dev/null 2>&1;  check "the lock can be taken again after unlock" "0" "$?"
b NEW_FUNCTIONALITY_CHECK_LOCK_STALE_SECS=0 bash "$HELPER" lock >/dev/null 2>&1; check "a stale lock is broken rather than blocking sweeps forever" "0" "$?"
b bash "$HELPER" unlock >/dev/null 2>&1

# ---------------------------------------------------------------------------
# verify-candidates: batch quote verification for a whole evaluator result
# ---------------------------------------------------------------------------
printf 'Added `omitClaudeMd` to agent frontmatter and\n`--agents` JSON so custom subagents run without CLAUDE.md.\n' > "$TMPDIR_T/slice-a.md"
printf 'Removed the `TaskOutput` tool; Claude reads a background task output file with Read.\n' > "$TMPDIR_T/slice-b.md"
cat > "$TMPDIR_T/batch.json" <<'JSON'
{"header": {"slice": "test", "items_reviewed": 4, "omitted_count": 0},
 "candidates": [
  {"verdict": "PROPOSE", "title": "real quote spanning a line break", "feature_key": "agent.omitClaudeMd", "target_type": "agent",
   "upstream": {"url": "https://code.claude.com/docs/en/changelog", "quote": "Added `omitClaudeMd` to agent frontmatter and `--agents` JSON"},
   "proposed_change": "x", "benefit": "H", "effort": "S", "risk": "low", "sensitive": false},
  {"verdict": "RISK-WATCH", "title": "real quote from the second slice", "feature_key": "tool.TaskOutput", "target_type": "agent",
   "upstream": {"url": "https://code.claude.com/docs/en/changelog", "quote": "Removed the `TaskOutput` tool; Claude reads a background task"},
   "proposed_change": "x", "benefit": "M", "effort": "S", "risk": "med", "sensitive": false},
  {"verdict": "PROPOSE", "title": "fabricated quote", "feature_key": "made.up", "target_type": "hook",
   "upstream": {"url": "https://code.claude.com/docs/en/changelog", "quote": "Added a magic flag that fixes every hook automatically"},
   "proposed_change": "x", "benefit": "H", "effort": "S", "risk": "low", "sensitive": false},
  {"verdict": "NO-ACTION", "title": "not checked", "feature_key": "desktop.x", "target_type": "other",
   "upstream": {"url": "https://code.claude.com/docs/en/whats-new/2026-w37", "quote": "this quote is not in any slice at all"},
   "reason_if_no_action": "Desktop-only"}
 ]}
JSON
OUT=$(h bash "$HELPER" verify-candidates "$TMPDIR_T/batch.json" "$TMPDIR_T/slice-a.md" "$TMPDIR_T/slice-b.md" 2>&1); RC=$?
check "a batch with a fabricated quote exits 1" "1" "$RC"
check_contains "candidate 1 verifies across a line break" "verified | 1 |" "$OUT"
check_contains "candidate 2 verifies from the second slice file" "verified | 2 |" "$OUT"
check_contains "the fabricated quote is called out by number and title" "NOT-VERIFIED | 3 | fabricated quote" "$OUT"
check_absent "NO-ACTION quotes are not checked (nothing actionable hangs on them)" "| 4 |" "$OUT"
check_contains "the batch ends with a count" "2 of 3 actionable quotes verified" "$OUT"
python3 - "$TMPDIR_T/batch.json" "$TMPDIR_T/batch-good.json" <<'MUTATE'
import json, sys
doc = json.load(open(sys.argv[1])); del doc["candidates"][2]; json.dump(doc, open(sys.argv[2], "w"))
MUTATE
h bash "$HELPER" verify-candidates "$TMPDIR_T/batch-good.json" "$TMPDIR_T/slice-a.md" "$TMPDIR_T/slice-b.md" >/dev/null 2>&1
check "a batch whose actionable quotes all verify exits 0" "0" "$?"
h bash "$HELPER" verify-candidates "$TMPDIR_T/batch-good.json" >/dev/null 2>&1
check "verify-candidates needs at least one slice file" "1" "$?"
# The single and the batch verifier must agree (same whitespace normalization).
h bash "$HELPER" verify-quote "$TMPDIR_T/slice-a.md" 'Added `omitClaudeMd` to agent frontmatter and `--agents` JSON' >/dev/null
check "verify-quote agrees with verify-candidates on the line-break case" "0" "$?"

# ---------------------------------------------------------------------------
# ledger-add: the helper renders rows and blocks, so a hand-typed table can never
# break next-id or ledger-check.
# ---------------------------------------------------------------------------
LA="$TMPDIR_T/add-ledger"; mkdir -p "$LA"
a() { h "CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$LA" "NEW_FUNCTIONALITY_CHECK_TODAY=2026-09-19" "$@"; }
cat > "$TMPDIR_T/curated.json" <<'JSON'
[
 {"verdict": "PROPOSE", "title": "Set omitClaudeMd on the review | specialists", "feature_key": "agent.omitClaudeMd", "target_type": "agent",
  "target_paths": ["~/.claude/agents/code-reviewer-security.md"],
  "upstream": {"source": "changelog", "ref": "2.1.271", "url": "https://code.claude.com/docs/en/changelog#2-1-271",
               "docs_url": "https://code.claude.com/docs/en/sub-agents", "quote": "Added omitClaudeMd to agent frontmatter\nand --agents JSON"},
  "today": "Every subagent loads the global CLAUDE.md.", "proposed_change": "Add omitClaudeMd: true to the five specialists.",
  "benefit": "H", "effort": "S", "risk": "low", "sensitive": false, "verify_before_adopting": "Confirm on the installed CLI."},
 {"verdict": "RISK-WATCH", "title": "Task tools are restricted on newer models", "feature_key": "tools.TaskCreate", "target_type": "agent",
  "target_paths": ["~/.claude/agents/code-reviewer.md"],
  "upstream": {"source": "changelog", "ref": "2.1.268", "url": "https://code.claude.com/docs/en/changelog#2-1-268", "quote": "Task-tracking tools restricted to older models"},
  "today": "Orchestrators list TaskCreate.", "proposed_change": "Check whether dispatch still works.",
  "benefit": "H", "effort": "M", "risk": "med", "sensitive": true, "verify_before_adopting": "Read the tools reference."}
]
JSON
OUT=$(a bash "$HELPER" ledger-add "$TMPDIR_T/curated.json"); RC=$?
check "ledger-add exits 0" "0" "$RC"
check_contains "the first proposal gets RW-0001" "RW-0001" "$OUT"
check_contains "the second proposal gets RW-0002" "RW-0002" "$OUT"
LEDGER_TEXT="$(cat "$LA/ledger.md")"; PROPOSALS_TEXT="$(cat "$LA/proposals.md")"
check_contains "a fresh ledger gets its three sections" "## Coverage" "$LEDGER_TEXT"
check_contains "the index row carries status, target, feature_key, upstream ref, date" "| RW-0001 | proposed | agent | agent.omitClaudeMd |" "$LEDGER_TEXT"
check_absent "a pipe inside a title cannot break the table" "review | specialists" "$LEDGER_TEXT"
check_contains "a risk-watch row is marked in its title" "| RW-0002 | proposed | agent | tools.TaskCreate | [RISK] Task tools" "$LEDGER_TEXT"
check_contains "index rows land above the run log" "## Run log" "$(printf '%s\n' "$LEDGER_TEXT" | sed -n '/RW-0002/,$p')"
check_contains "each proposal gets a detail block" "### RW-0001 · agent · Set omitClaudeMd" "$PROPOSALS_TEXT"
check_contains "the quote is stored as a one-line blockquote (data, not instructions)" "  > Added omitClaudeMd to agent frontmatter and --agents JSON" "$PROPOSALS_TEXT"
check_contains "a sensitive proposal is flagged in its block" "**Sensitive:** YES" "$PROPOSALS_TEXT"
check_contains "the block records what to verify first" "Confirm on the installed CLI." "$PROPOSALS_TEXT"
a bash "$HELPER" ledger-check >/dev/null 2>&1
check "a ledger written by ledger-add passes ledger-check" "0" "$?"

OUT=$(a bash "$HELPER" ledger-add "$TMPDIR_T/curated.json" 2>&1); RC=$?
check_contains "re-adding the same feature_key + target is skipped, not duplicated" "skipped (already in the ledger)" "$OUT"
check "after a skipped duplicate the ledger still has two rows" "2" "$(grep -c '^| RW-' "$LA/ledger.md")"
python3 - "$TMPDIR_T/curated.json" "$TMPDIR_T/curated-new.json" <<'MUTATE'
import json, sys
doc = json.load(open(sys.argv[1])); doc = [doc[0]]; doc[0]["feature_key"] = "hooks.if"; doc[0]["target_type"] = "hook"; doc[0]["title"] = "Add if conditions"
json.dump(doc, open(sys.argv[2], "w"))
MUTATE
OUT=$(a bash "$HELPER" ledger-add "$TMPDIR_T/curated-new.json")
check_contains "numbering continues across calls" "RW-0003" "$OUT"
printf '{"not": "a list"}\n' > "$TMPDIR_T/curated-bad.json"
a bash "$HELPER" ledger-add "$TMPDIR_T/curated-bad.json" >/dev/null 2>&1
check "ledger-add rejects input that is not a list of candidates" "1" "$?"

# ---------------------------------------------------------------------------
# Independent-review fixes (2026-09-19). Each block names the defect it pins.
# ---------------------------------------------------------------------------

# Host allowlist: the host is matched as TEXT, never as a glob pattern.
check "a glob-star host is refused"    "1" "$(hosts 'https://*.com/x')"
check "a bracket-glob host is refused" "1" "$(hosts 'https://[!x]*/y')"

# scrub-check fails CLOSED: with no per-machine denylist a "clean" verdict would be
# vacuous, and the agenda is the one thing that leaves the machine.
NODEN="$TMPDIR_T/noden-ledger"; mkdir -p "$NODEN"
n() { h "CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$NODEN" "NEW_FUNCTIONALITY_CHECK_SCRUB_USER=someuser" "NEW_FUNCTIONALITY_CHECK_SCRUB_HOME=/home/someuser" "NEW_FUNCTIONALITY_CHECK_SCRUB_HOST=somehost" "$@"; }
OUT=$(n bash "$HELPER" scrub-check "$TMPDIR_T/agenda-clean.txt" 2>&1); RC=$?
check "scrub-check refuses to pass when the machine has no denylist" "1" "$RC"
check_contains "the refusal names the missing denylist" "denylist" "$OUT"
check_absent "a missing denylist never prints a clean verdict" "scrub-check: clean" "$OUT"
printf '# only a comment\n\n' > "$NODEN/denylist.txt"
n bash "$HELPER" scrub-check "$TMPDIR_T/agenda-clean.txt" >/dev/null 2>&1
check "a denylist with no terms is refused too (a vacuous pass is not a pass)" "1" "$?"
printf 'Globex\n' > "$NODEN/denylist.txt"
n bash "$HELPER" scrub-check "$TMPDIR_T/agenda-clean.txt" >/dev/null 2>&1
check "once the denylist has a term, a clean agenda passes again" "0" "$?"

# ledger-check: a typo in one id is a reported problem; it must not kill the shell
# and silently skip every later row.
ML="$TMPDIR_T/malformed-ledger"; mkdir -p "$ML"
m() { h "CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$ML" "$@"; }
cat > "$ML/ledger.md" <<'LEDGER'
## Proposal index

| ID | status | target | feature_key | title | upstream | logged | decided |
|---|---|---|---|---|---|---|---|
| RW-0001 | proposed | hook | hooks.if | first | 2026-w13 | 2026-09-19 | |
| RW-12abc | proposed | hook | hooks.x | typo id | 2026-w13 | 2026-09-19 | |
| RW-0007 | totally-bogus-status | hook | hooks.y | later row | 2026-w13 | 2026-09-19 | |
LEDGER
printf '### RW-0001 · hook · first\n\nbody\n\n### RW-0007 · hook · later row\n\nbody\n' > "$ML/proposals.md"
OUT=$(m bash "$HELPER" ledger-check 2>&1); RC=$?
check "a malformed id is a reported problem" "1" "$RC"
check_contains "the malformed id is named" "RW-12abc" "$OUT"
check_contains "rows after a malformed id are still checked" "totally-bogus-status" "$OUT"
check_absent "no arithmetic error leaks out of ledger-check" "value too great" "$OUT"

# The single and the batch quote verifier share ONE normalizer: any whitespace run
# (form feed, non-breaking space from rendered HTML) equals one space in both.
printf 'Added the `fooBar` setting so that\fsubagents can skip the global file entirely.\n' > "$TMPDIR_T/slice-ff.md"
printf 'Launching the new plan so\302\240that every seat gets the feature this week.\n' > "$TMPDIR_T/slice-nbsp.md"
cat > "$TMPDIR_T/batch-ws.json" <<'JSON'
{"header": {"slice": "test", "items_reviewed": 2, "omitted_count": 0},
 "candidates": [
  {"verdict": "PROPOSE", "title": "form feed", "feature_key": "x.ff", "target_type": "agent",
   "upstream": {"url": "https://code.claude.com/docs/en/changelog", "quote": "Added the `fooBar` setting so that subagents can skip"},
   "proposed_change": "x", "benefit": "H", "effort": "S", "risk": "low", "sensitive": false},
  {"verdict": "PROPOSE", "title": "non-breaking space", "feature_key": "x.nbsp", "target_type": "settings",
   "upstream": {"url": "https://support.claude.com/en/articles/12138966-release-notes", "quote": "Launching the new plan so that every seat gets the feature"},
   "proposed_change": "x", "benefit": "H", "effort": "S", "risk": "low", "sensitive": false}
 ]}
JSON
h bash "$HELPER" verify-candidates "$TMPDIR_T/batch-ws.json" "$TMPDIR_T/slice-ff.md" "$TMPDIR_T/slice-nbsp.md" >/dev/null 2>&1
check "the batch verifier treats a form feed and a non-breaking space as whitespace" "0" "$?"
h bash "$HELPER" verify-quote "$TMPDIR_T/slice-ff.md" 'Added the `fooBar` setting so that subagents can skip' >/dev/null 2>&1
check "verify-quote agrees with the batch verifier on a form feed" "0" "$?"
h bash "$HELPER" verify-quote "$TMPDIR_T/slice-nbsp.md" 'Launching the new plan so that every seat gets the feature' >/dev/null 2>&1
check "verify-quote agrees with the batch verifier on a non-breaking space" "0" "$?"
h bash "$HELPER" verify-quote "$TMPDIR_T/slice-ff.md" 'Added a magic flag that fixes every hook automatically' >/dev/null 2>&1
check "a fabricated quote still fails after the normalizer change" "1" "$?"
h bash "$HELPER" verify-quote "$TMPDIR_T/slice-ff.md" 'too short' >/dev/null 2>&1
check "a quote under the minimum length still proves nothing" "1" "$?"

# Lock: a lock directory with no timestamp is NOT infinitely old. Its own mtime decides.
LK="$TMPDIR_T/lock-ledger"; mkdir -p "$LK/.lock"
k() { h "CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$LK" "$@"; }
k bash "$HELPER" lock >/dev/null 2>&1
check "a fresh lock with no timestamp file is respected, not stolen" "1" "$?"
touch -t 202001010000 "$LK/.lock"
OUT=$(k bash "$HELPER" lock 2>&1); RC=$?
check "an old lock with no timestamp file is broken as stale" "0" "$RC"
check_contains "breaking a stale lock says so" "stale" "$OUT"
k bash "$HELPER" unlock >/dev/null 2>&1

# Deadline: a backoff sleep longer than the remaining budget is never slept, so the
# per-source table always prints before the Bash tool's own timeout.
STARTED=$(date +%s)
OUT=$(fetch_env "NEW_FUNCTIONALITY_CHECK_URL_INDEX=http://127.0.0.1:9/whats-new.md" NEW_FUNCTIONALITY_CHECK_RETRY_ATTEMPTS=4 \
      NEW_FUNCTIONALITY_CHECK_RETRY_BASE_SECS=8 NEW_FUNCTIONALITY_CHECK_DEADLINE_SECS=2 bash "$HELPER" fetch 2>"$TMPDIR_T/deadline.err"); RC=$?
ELAPSED=$(( $(date +%s) - STARTED ))
if [ "$ELAPSED" -lt 6 ]; then check "a backoff longer than the remaining deadline is skipped" "fast" "fast"; else check "a backoff longer than the remaining deadline is skipped" "fast" "slept ${ELAPSED}s"; fi
check_contains "the per-source table still prints when the deadline cuts retries short" "whats-new-index | core | FAILED" "$OUT"
check_contains "the cut-short retry says the deadline was the reason" "deadline" "$OUT$(cat "$TMPDIR_T/deadline.err")"
check "a deadline-limited fetch is a partial run" "2" "$RC"

# Retry-After (pure): seconds honored, capped, CRLF-safe; an HTTP-date is ignored.
ra() { h bash "$HELPER" _retry-after "$1" 2>/dev/null; }
printf 'HTTP/2 429\nretry-after: 7\n\n' > "$TMPDIR_T/hdr-plain.txt"
printf 'HTTP/2 429\r\nRetry-After: 900\r\n\r\n' > "$TMPDIR_T/hdr-capped.txt"
printf 'HTTP/2 503\r\nRetry-After: 12\r\n\r\n' > "$TMPDIR_T/hdr-crlf.txt"
printf 'HTTP/2 503\nRetry-After: Wed, 21 Oct 2026 07:28:00 GMT\n\n' > "$TMPDIR_T/hdr-date.txt"
printf 'HTTP/2 500\ncontent-type: text/html\n\n' > "$TMPDIR_T/hdr-none.txt"
check "Retry-After seconds are honored"                     "7"  "$(ra "$TMPDIR_T/hdr-plain.txt")"
check "Retry-After is capped at the backoff ceiling"        "30" "$(ra "$TMPDIR_T/hdr-capped.txt")"
check "Retry-After survives CRLF line endings"              "12" "$(ra "$TMPDIR_T/hdr-crlf.txt")"
check "an HTTP-date Retry-After falls back to the backoff"  ""   "$(ra "$TMPDIR_T/hdr-date.txt")"
check "no Retry-After header means no override"             ""   "$(ra "$TMPDIR_T/hdr-none.txt")"
check "a missing header file means no override"             ""   "$(ra "$TMPDIR_T/hdr-missing.txt")"

# Validator caps are calibrated to what careful agents write, and stated in the agent files.
# They are SOFT at validation — a field up to twice its cap is flagged OVERLONG (reword it
# during curation, never log it verbatim) because losing a whole lane to a title that ran
# 12 characters long is a worse failure than the one the cap prevents — and HARD at the
# write gate: ledger-add refuses an over-cap field, so nothing over-long reaches the ledger.
# More than twice the cap still rejects the whole result: that is an agent dumping text.
python3 - "$TMPDIR_T/eval-good.json" "$TMPDIR_T" <<'MUTATE'
import json, sys
base, out = json.load(open(sys.argv[1])), sys.argv[2]
def write(name, mutate):
    doc = json.loads(json.dumps(base)); mutate(doc); json.dump(doc, open("%s/%s" % (out, name), "w"))
write("cap-slice-ok.json",  lambda d: d["header"].__setitem__("slice", "s" * 400))
write("cap-slice-bad.json", lambda d: d["header"].__setitem__("slice", "s" * 401))
write("cap-today-ok.json",  lambda d: d["candidates"][0].__setitem__("today", "t" * 1200))
write("cap-today-bad.json", lambda d: d["candidates"][0].__setitem__("today", "t" * 1201))
MUTATE
for NAME in slice today; do
    OUT=$(h bash "$HELPER" validate-candidates evaluator "$TMPDIR_T/cap-$NAME-ok.json" 2>&1); RC=$?
    check "a $NAME at its cap is valid" "0" "$RC"
    check_absent "a $NAME at its cap is not flagged" "OVERLONG" "$OUT"
    OUT=$(h bash "$HELPER" validate-candidates evaluator "$TMPDIR_T/cap-$NAME-bad.json" 2>&1); RC=$?
    check "a $NAME one character over its cap does not lose the lane" "0" "$RC"
    check_contains "a $NAME one character over its cap is flagged for rewording" "OVERLONG" "$OUT"
    check_contains "the verdict line counts the over-long fields" "1 over-long" "$OUT"
done
python3 - "$TMPDIR_T/eval-good.json" "$TMPDIR_T/cap-title-gross.json" <<'MUTATE'
import json, sys
doc = json.load(open(sys.argv[1])); doc["candidates"][0]["title"] = "t" * 321
json.dump(doc, open(sys.argv[2], "w"))
MUTATE
h bash "$HELPER" validate-candidates evaluator "$TMPDIR_T/cap-title-gross.json" >/dev/null 2>&1
check "a field more than twice its cap still rejects the whole result" "1" "$?"
python3 - "$TMPDIR_T/research-good.json" "$TMPDIR_T" <<'MUTATE'
import json, sys
base, out = json.load(open(sys.argv[1])), sys.argv[2]
for name, size in (("cap-claim-ok.json", 900), ("cap-claim-bad.json", 901)):
    doc = json.loads(json.dumps(base)); doc["leads"][0]["claim"] = "c" * size
    json.dump(doc, open("%s/%s" % (out, name), "w"))
MUTATE
h bash "$HELPER" validate-candidates researcher "$TMPDIR_T/cap-claim-ok.json" >/dev/null 2>&1
check "a claim at its cap is valid" "0" "$?"
OUT=$(h bash "$HELPER" validate-candidates researcher "$TMPDIR_T/cap-claim-bad.json" 2>&1); RC=$?
check "a claim one character over its cap does not lose the lane" "0" "$RC"
check_contains "a claim one character over its cap is flagged for rewording" "OVERLONG lead 1: claim" "$OUT"

# Changelog drift everywhere is a PARSE error (exit 3), never just "partial".
printf '# Changelog\n\n### v9 renamed headings\n- Added x\n' > "$SRC/changelog-drifted-mirror.md"
OUT=$(fetch_env "NEW_FUNCTIONALITY_CHECK_URL_CHANGELOG=$(file_url "$SRC/changelog-drifted.md")" \
      "NEW_FUNCTIONALITY_CHECK_URL_CHANGELOG_MIRROR=$(file_url "$SRC/changelog-drifted-mirror.md")" \
      "NEW_FUNCTIONALITY_CHECK_LOCAL_CHANGELOG=$SRC/nope3.md" bash "$HELPER" fetch 2>/dev/null); RC=$?
check_contains "a changelog that parses nowhere is a core failure" "changelog | core | FAILED" "$OUT"
check "changelog format drift with no usable source exits 3, not 2" "3" "$RC"

# The canary cannot run without npm latest: reported as skipped, counted apart from failures.
OUT=$(fetch_env "NEW_FUNCTIONALITY_CHECK_CACHE_DIR=$TMPDIR_T/fcache-no-npm" "NEW_FUNCTIONALITY_CHECK_URL_NPM_LATEST=$(file_url "$SRC/nope-npm.json")" bash "$HELPER" fetch 2>/dev/null); RC=$?
check_contains "a canary that cannot run is skipped, in the extended class" "changelog-canary | extended | SKIPPED" "$OUT"
check_contains "skips are counted apart from failures" "1 skipped" "$OUT"
check "a skipped safety check is never a clean run" "2" "$RC"

# watch-diff: the summary counts everything; the rendered diff is capped for the context window.
BCACHE="$TMPDIR_T/big-cache"; BLEDGER="$TMPDIR_T/big-ledger"; mkdir -p "$BCACHE" "$BLEDGER"
bw() { h "NEW_FUNCTIONALITY_CHECK_CACHE_DIR=$BCACHE" "CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$BLEDGER" NEW_FUNCTIONALITY_CHECK_FLOOR_DOCS_INDEX=1 NEW_FUNCTIONALITY_CHECK_FLOOR_BEST_PRACTICES=1 NEW_FUNCTIONALITY_CHECK_FLOOR_MARKETPLACE=1 "$@"; }
awk 'BEGIN { for (i = 1; i <= 400; i++) print "- [Old page " i "](https://x/old" i ".md): old" }' > "$BCACHE/llms.txt"
printf '# Best practices\n\nVerify your work.\n' > "$BCACHE/best-practices.md"
printf '{"plugins":[{"name":"superpowers","version":"6.3.0"}]}\n' > "$BCACHE/marketplace.json"
bw bash "$HELPER" watch-diff >/dev/null 2>&1; bw bash "$HELPER" watch-commit >/dev/null 2>&1
awk 'BEGIN { for (i = 1; i <= 400; i++) print "- [New page " i "](https://x/new" i ".md): new" }' > "$BCACHE/llms.txt"
OUT=$(bw bash "$HELPER" watch-diff 2>&1)
check_contains "a large diff still reports its true size" "docs-index: 400 added, 400 removed" "$OUT"
check "a large diff renders at most 200 changed lines" "200" "$(printf '%s\n' "$OUT" | grep -c '^[+-] ')"
check_contains "the cut is announced, never silent" "600 more changed line(s) not shown" "$OUT"

# ledger-add dedupes against a HAND-WRITTEN row in the documented 8-column shape,
# and replaces the ledger atomically (no temp file left behind).
HL="$TMPDIR_T/hand-ledger"; mkdir -p "$HL"
hl() { h "CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$HL" "NEW_FUNCTIONALITY_CHECK_TODAY=2026-09-19" "$@"; }
cat > "$HL/ledger.md" <<'LEDGER'
# New-Functionality Check Ledger

## Coverage

| source | covered through | last run UTC |
|---|---|---|

## Proposal index

| ID | status | target | feature_key | title | upstream | logged | decided |
|---|---|---|---|---|---|---|---|
| RW-0001 | accepted | agent | agent.omitClaudeMd | typed by hand | 2.1.271 | 2026-09-12 | 2026-09-13 |

## Run log

LEDGER
printf '### RW-0001 · agent · typed by hand\n\nbody\n' > "$HL/proposals.md"
OUT=$(hl bash "$HELPER" ledger-add "$TMPDIR_T/curated.json" 2>&1)
check_contains "a hand-written row with the same feature_key + target blocks a duplicate" "skipped (already in the ledger)" "$OUT"
check_contains "the other candidate is still added after the hand-written row" "RW-0002" "$OUT"
check "the hand-written ledger ends with exactly two rows" "2" "$(grep -c '^| RW-' "$HL/ledger.md")"
check "ledger-add leaves no temp file behind" "0" "$(ls -A "$HL" | grep -c '\.tmp')"
hl bash "$HELPER" ledger-check >/dev/null 2>&1
check "the hand-written ledger still passes ledger-check after ledger-add" "0" "$?"

# ledger-add is the WRITE gate for length caps: an over-cap field is refused and nothing is written.
WG="$TMPDIR_T/gate-ledger"; mkdir -p "$WG"
wg() { h "CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$WG" "NEW_FUNCTIONALITY_CHECK_TODAY=2026-09-19" "$@"; }
python3 - "$TMPDIR_T/curated.json" "$TMPDIR_T/curated-long.json" <<'MUTATE'
import json, sys
doc = json.load(open(sys.argv[1])); doc[1]["title"] = "t" * 161
json.dump(doc, open(sys.argv[2], "w"))
MUTATE
OUT=$(wg bash "$HELPER" ledger-add "$TMPDIR_T/curated-long.json" 2>&1); RC=$?
check "ledger-add refuses a curated field over its cap" "1" "$RC"
check_contains "the refusal names the item and the field" "item 2: title" "$OUT"
if [ -f "$WG/ledger.md" ]; then check "a refused batch writes nothing, not even the valid items" "absent" "present"; else check "a refused batch writes nothing, not even the valid items" "absent" "absent"; fi

# verify-lead is polite: a page it fetched moments ago is reused, not fetched once per
# quote (the first backfill tripped the docs site's rate limit doing exactly that).
LEADC="$TMPDIR_T/lead-cache"; mkdir -p "$LEADC"
printf '# Hooks\n\nThe if field uses permission rule syntax to filter when a hook runs at all.\nA second sentence about exec form and the args array.\n' > "$SRC/lead-page.md"
lc() { h "NEW_FUNCTIONALITY_CHECK_CACHE_DIR=$LEADC" "NEW_FUNCTIONALITY_CHECK_CURL_PROTO==https,http,file" NEW_FUNCTIONALITY_CHECK_VERIFY_ANY_HOST=1 NEW_FUNCTIONALITY_CHECK_RETRY_ATTEMPTS=1 "$@"; }
lc bash "$HELPER" verify-lead "$(file_url "$SRC/lead-page.md")" "The if field uses permission rule syntax" >/dev/null 2>&1
check "a lead page is fetched and verified the first time" "0" "$?"
mv "$SRC/lead-page.md" "$SRC/lead-page.gone"
OUT=$(lc bash "$HELPER" verify-lead "$(file_url "$SRC/lead-page.md")" "A second sentence about exec form" 2>&1); RC=$?
check "a second quote from the same page is served from the fresh copy (no refetch)" "0" "$RC"
check_contains "reusing the fresh copy is said out loud" "reusing" "$OUT"
lc NEW_FUNCTIONALITY_CHECK_LEAD_CACHE_FRESH_SECS=0 bash "$HELPER" verify-lead "$(file_url "$SRC/lead-page.md")" "A second sentence about exec form" >/dev/null 2>&1
check "a stale copy is never trusted: the page is fetched again (and here that fails)" "2" "$?"

# save-result: a subagent's reply is recovered from its transcript (or, failing that, from the
# pasted notification text) — never retyped, and never trusted unless it is strict JSON.
python3 - "$TMPDIR_T/transcript.jsonl" "$TMPDIR_T/transcript-prose.jsonl" <<'MAKE'
import json, sys
def line(kind, content):
    return json.dumps({"type": kind, "message": {"role": kind, "content": content}})
reply_a = '```json\n{"header": {"slice": "t", "items_reviewed": 1, "omitted_count": 0},\n "candidates": [{"title": "split mid-wo'
reply_b = 'rd here"}]}\n```'
rows = [line("user", "dispatch prompt with a {brace} in it"),
        line("assistant", [{"type": "text", "text": "Let me read the slice {first}."}]),
        line("assistant", [{"type": "tool_use", "name": "Read", "input": {}}]),
        line("user", [{"type": "tool_result", "content": "slice text"}]),
        line("assistant", [{"type": "thinking", "thinking": "..."}]),
        line("assistant", [{"type": "text", "text": reply_a}]),
        line("user", "Output token limit hit. Resume directly — no apology, no recap of what you were doing."),
        line("assistant", [{"type": "text", "text": reply_b}])]
open(sys.argv[1], "w").write("\n".join(rows) + "\n")
open(sys.argv[2], "w").write("\n".join(rows[:4] + [line("assistant", [{"type": "text", "text": "I could not finish the task."}])]) + "\n")
MAKE
OUT=$(h bash "$HELPER" save-result "$TMPDIR_T/saved.json" "$TMPDIR_T/transcript.jsonl" 2>&1); RC=$?
check "save-result recovers a reply from its transcript" "0" "$RC"
check_contains "a reply split by the output-token limit is rejoined" "2 piece" "$OUT"
check "the rejoined reply is the agent's own JSON (text before the last tool result is ignored)" "split mid-word here" \
      "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["candidates"][0]["title"])' "$TMPDIR_T/saved.json" 2>/dev/null)"
printf '[harness note about neutralized tags]\n```json\n{"header": {"lanes_completed": ["x"]}, "leads": [{"title": "a &lt;code&gt;tag&lt;/code&gt; &amp; more"}]}\n```\n' \
    | h bash "$HELPER" save-result "$TMPDIR_T/saved-stdin.json" >/dev/null 2>&1
check "save-result also accepts pasted notification text on stdin" "0" "$?"
check "pasted text is HTML-unescaped (the harness escapes instruction-shaped output)" "a <code>tag</code> & more" \
      "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["leads"][0]["title"])' "$TMPDIR_T/saved-stdin.json" 2>/dev/null)"
h bash "$HELPER" save-result "$TMPDIR_T/saved-prose.json" "$TMPDIR_T/transcript-prose.jsonl" >/dev/null 2>&1
check "a reply with no JSON object is an error" "1" "$?"
if [ -e "$TMPDIR_T/saved-prose.json" ]; then check "a failed save-result writes nothing" "absent" "present"; else check "a failed save-result writes nothing" "absent" "absent"; fi
h bash "$HELPER" save-result "$TMPDIR_T/saved-missing.json" "$TMPDIR_T/no-such-transcript.jsonl" >/dev/null 2>&1
check "a missing transcript is an error, never an empty result" "1" "$?"
# Newer Claude Code subagents hand their report back through a SubagentHandback tool call:
# the JSON is that call's input.message, followed by a tool result and closing prose
# (observed 2026-10-09: the first weekly researcher lane failed save-result on exactly this).
python3 - "$TMPDIR_T/transcript-handback.jsonl" <<'MAKE'
import json, sys
def line(kind, content):
    return json.dumps({"type": kind, "message": {"role": kind, "content": content}})
report = '{"header": {"lanes_completed": ["x"]}, "leads": [{"title": "handed back via the tool call"}]}'
rows = [line("user", "dispatch prompt"),
        line("assistant", [{"type": "tool_use", "name": "WebFetch", "input": {}}]),
        line("user", [{"type": "tool_result", "content": "page"}]),
        line("assistant", [{"type": "tool_use", "name": "SubagentHandback", "input": {"message": report}}]),
        line("user", [{"type": "tool_result", "content": [{"type": "text", "text": "{\"success\":true}"}]}]),
        line("assistant", [{"type": "text", "text": "The report was delivered to the caller through SubagentHandback."}])]
open(sys.argv[1], "w").write("\n".join(rows) + "\n")
MAKE
OUT=$(h bash "$HELPER" save-result "$TMPDIR_T/saved-handback.json" "$TMPDIR_T/transcript-handback.jsonl" 2>&1); RC=$?
check "save-result recovers a reply handed back through the SubagentHandback tool call" "0" "$RC"
check "the handed-back JSON is the agent's own (not the closing prose)" "handed back via the tool call" \
      "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["leads"][0]["title"])' "$TMPDIR_T/saved-handback.json" 2>/dev/null)"
# An agent may hand back twice (a corrected report): the last handback wins. A blank or
# whitespace-only handback is no reply at all: it is skipped, and the assistant's text is used.
python3 - "$TMPDIR_T/transcript-two-handbacks.jsonl" "$TMPDIR_T/transcript-blank-handback.jsonl" <<'MAKE'
import json, sys
def line(kind, content):
    return json.dumps({"type": kind, "message": {"role": kind, "content": content}})
def handback(message):
    return line("assistant", [{"type": "tool_use", "name": "SubagentHandback", "input": {"message": message}}])
done = line("user", [{"type": "tool_result", "content": [{"type": "text", "text": "{\"success\":true}"}]}])
first = '{"header": {"lanes_completed": ["x"]}, "leads": [{"title": "first handback"}]}'
second = '{"header": {"lanes_completed": ["x"]}, "leads": [{"title": "second handback"}]}'
text_reply = '{"header": {"lanes_completed": ["x"]}, "leads": [{"title": "from the text reply"}]}'
two = [line("user", "dispatch prompt"), handback(first), done, handback(second), done,
       line("assistant", [{"type": "text", "text": "Both reports were delivered."}])]
blank = [line("user", "dispatch prompt"), handback(""), done, handback("  \n\t "), done,
         line("assistant", [{"type": "text", "text": text_reply}])]
open(sys.argv[1], "w").write("\n".join(two) + "\n")
open(sys.argv[2], "w").write("\n".join(blank) + "\n")
MAKE
h bash "$HELPER" save-result "$TMPDIR_T/saved-two-handbacks.json" "$TMPDIR_T/transcript-two-handbacks.jsonl" >/dev/null 2>&1
check "save-result accepts a transcript with two SubagentHandback calls" "0" "$?"
check "the last SubagentHandback wins" "second handback" \
      "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["leads"][0]["title"])' "$TMPDIR_T/saved-two-handbacks.json" 2>/dev/null)"
h bash "$HELPER" save-result "$TMPDIR_T/saved-blank-handback.json" "$TMPDIR_T/transcript-blank-handback.jsonl" >/dev/null 2>&1
check "a blank or whitespace-only SubagentHandback is skipped, not saved as an empty reply" "0" "$?"
check "with only blank handbacks, the assistant's text reply is saved" "from the text reply" \
      "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["leads"][0]["title"])' "$TMPDIR_T/saved-blank-handback.json" 2>/dev/null)"

# ledger-status: a decision changes the index row AND the detail block together, or nothing.
DL="$TMPDIR_T/decision-ledger"; mkdir -p "$DL"
d() { h "CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$DL" "NEW_FUNCTIONALITY_CHECK_TODAY=2026-09-20" "$@"; }
h "CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$DL" "NEW_FUNCTIONALITY_CHECK_TODAY=2026-09-19" bash "$HELPER" ledger-add "$TMPDIR_T/curated.json" >/dev/null 2>&1
OUT=$(d bash "$HELPER" ledger-status RW-0001 accepted 2>&1); RC=$?
check "ledger-status records an acceptance" "0" "$RC"
check_contains "the index row carries the new status and the decision date" "| RW-0001 | accepted | agent | agent.omitClaudeMd |" "$(cat "$DL/ledger.md")"
check_contains "the decided column is filled in" "| 2026-09-19 | 2026-09-20 |" "$(grep '^| RW-0001 ' "$DL/ledger.md")"
check_contains "the detail block's status line follows" "- **Status:** accepted (decided 2026-09-20)" "$(cat "$DL/proposals.md")"
check_contains "the history line keeps the earlier entry and appends the new one" "- **History:** 2026-09-19 proposed · 2026-09-20 accepted" "$(cat "$DL/proposals.md")"
check_contains "the other proposal is untouched" "| RW-0002 | proposed |" "$(cat "$DL/ledger.md")"
d bash "$HELPER" ledger-status RW-0002 declined "not worth | the churn
right now" >/dev/null 2>&1
check "a decline with a reason is recorded" "0" "$?"
check_contains "the reason is stored pipe-free and on one line" "| RW-0002 | declined — not worth / the churn right now |" "$(cat "$DL/ledger.md")"
d bash "$HELPER" ledger-check >/dev/null 2>&1
check "the ledger still passes ledger-check after two decisions" "0" "$?"
BEFORE="$(cat "$DL/ledger.md" "$DL/proposals.md" | cksum)"
d bash "$HELPER" ledger-status RW-0001 declined >/dev/null 2>&1
check "a decline without a reason is refused" "1" "$?"
d bash "$HELPER" ledger-status RW-0001 deferred >/dev/null 2>&1
check "a deferral without an until is refused" "1" "$?"
d bash "$HELPER" ledger-status RW-0001 applied >/dev/null 2>&1
check "applied without evidence is refused" "1" "$?"
d bash "$HELPER" ledger-status RW-0001 maybe-later "x" >/dev/null 2>&1
check "a status outside the vocabulary is refused" "1" "$?"
d bash "$HELPER" ledger-status RW-0099 accepted >/dev/null 2>&1
check "an unknown id is refused" "1" "$?"
d bash "$HELPER" ledger-status "RW-1; rm" accepted >/dev/null 2>&1
check "a malformed id is refused" "1" "$?"
check "every refused decision leaves both files byte-identical" "$BEFORE" "$(cat "$DL/ledger.md" "$DL/proposals.md" | cksum)"
check "ledger-status leaves no temp file behind" "0" "$(ls -A "$DL" | grep -c '\.tmp')"

# ---------------------------------------------------------------------------
# backup: an off-disk copy of the ledger (the ledger dir is outside every other backup).
# ---------------------------------------------------------------------------
BK="$TMPDIR_T/backup-ledger"; mkdir -p "$BK/archive/20260101T000000Z" "$BK/snapshots"
k() { h "CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$BK" "$@"; }
printf '# New-Functionality Check Ledger\n' > "$BK/ledger.md"; printf '### RW-0001\n' > "$BK/proposals.md"
printf 'private-term\n' > "$BK/denylist.txt"; printf 'page baseline\n' > "$BK/snapshots/llms.txt"
printf 'old copy\n' > "$BK/archive/20260101T000000Z/ledger.md"
BKOUT="$TMPDIR_T/backup-target"; mkdir -p "$BKOUT"

OUT=$(k bash "$HELPER" backup 2>&1); RC=$?
check "backup with no target and no backup.conf is refused" "1" "$RC"
check_contains "the refusal says how to configure a target" "backup.conf" "$OUT"
OUT=$(k bash "$HELPER" backup "$TMPDIR_T/no-such-dir" 2>&1); RC=$?
check "backup into a missing directory is refused" "1" "$RC"
check "a refused backup creates nothing" "0" "$(ls "$TMPDIR_T" | grep -c '^no-such-dir$')"

OUT=$(k bash "$HELPER" backup "$BKOUT" 2>&1); RC=$?
check "backup into an existing directory succeeds" "0" "$RC"
TARBALL="$(ls "$BKOUT"/claude_code_new_functionality_check_ledger_*.tar.gz 2>/dev/null | head -1)"
[ -n "$TARBALL" ] || TARBALL="NO-TARBALL-WRITTEN"   # an empty needle would match any output
check "exactly one dated tarball was written" "1" "$(ls "$BKOUT"/claude_code_new_functionality_check_ledger_*.tar.gz 2>/dev/null | wc -l | tr -d ' ')"
check_contains "backup prints the file it wrote" "$TARBALL" "$OUT"
# An empty name would make tar wait on stdin, so list only a tarball that exists.
LISTING=""; [ -f "$TARBALL" ] && LISTING="$(tar -tzf "$TARBALL" 2>/dev/null </dev/null)"
if [ -n "$LISTING" ]; then check "the tarball can be listed" "yes" "yes"; else check "the tarball can be listed" "yes" "no (nothing to list)"; fi
check_contains "the tarball holds the ledger index" "ledger.md" "$LISTING"
check_contains "the tarball holds the proposal blocks" "proposals.md" "$LISTING"
check_contains "the tarball holds the watched-page baselines" "snapshots/llms.txt" "$LISTING"
check_absent   "the ledger's own same-disk archive is left out" "archive/" "$LISTING"
check "backup leaves no temp file behind" "0" "$(ls -A "$BKOUT" | grep -c '\.tmp')"

BKSAME="$TMPDIR_T/backup-same-second"; mkdir -p "$BKSAME"
k env NEW_FUNCTIONALITY_CHECK_BACKUP_STAMP=20260101T000000Z bash "$HELPER" backup "$BKSAME" >/dev/null 2>&1
FIRST_SUM="$(cksum < "$BKSAME/claude_code_new_functionality_check_ledger_20260101T000000Z.tar.gz" 2>/dev/null)"
printf 'a later edit\n' >> "$BK/leads.md"
k env NEW_FUNCTIONALITY_CHECK_BACKUP_STAMP=20260101T000000Z bash "$HELPER" backup "$BKSAME" >/dev/null 2>&1
check "a second backup in the same second gets its own name" "yes" "$([ -f "$BKSAME/claude_code_new_functionality_check_ledger_20260101T000000Z_2.tar.gz" ] && echo yes || echo no)"
check "and the first backup is byte-identical afterwards" "$FIRST_SUM" "$(cksum < "$BKSAME/claude_code_new_functionality_check_ledger_20260101T000000Z.tar.gz" 2>/dev/null)"
OUT=$(k bash "$HELPER" backup "$BK/snapshots" 2>&1); RC=$?
check "a target inside the ledger itself is refused (that is not off this disk)" "1" "$RC"
check "and nothing was written into the ledger" "0" "$(ls "$BK/snapshots" | grep -c 'claude_code_new_functionality_check_ledger_')"

BKCONF="$TMPDIR_T/backup-target-from-conf"; mkdir -p "$BKCONF"
printf '# per-machine backup target\nBACKUP_DIR=%s\n' "$BKCONF" > "$BK/backup.conf"
OUT=$(k bash "$HELPER" backup 2>&1); RC=$?
check "with backup.conf the target needs no argument" "0" "$RC"
check "the tarball landed in the configured directory" "1" "$(ls "$BKCONF"/claude_code_new_functionality_check_ledger_*.tar.gz 2>/dev/null | wc -l | tr -d ' ')"

EMPTYL="$TMPDIR_T/backup-empty-ledger"; mkdir -p "$EMPTYL"
OUT=$(h "CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR=$EMPTYL" bash "$HELPER" backup "$BKOUT" 2>&1); RC=$?
check "a machine with no ledger has nothing to back up" "1" "$RC"

# backup.conf is hand-edited, possibly on Windows: quotes, trailing blanks and a CR must not break the path.
BKQ="$TMPDIR_T/backup target quoted"; mkdir -p "$BKQ"
printf 'BACKUP_DIR="%s"   \r\n' "$BKQ" > "$BK/backup.conf"
OUT=$(k bash "$HELPER" backup 2>&1); RC=$?
check "a quoted BACKUP_DIR with trailing blanks and a CR still works" "0" "$RC"
check "the tarball landed in the quoted directory" "1" "$(ls "$BKQ"/claude_code_new_functionality_check_ledger_*.tar.gz 2>/dev/null | wc -l | tr -d ' ')"
printf 'BACKUP_DIR=\n' > "$BK/backup.conf"
OUT=$(k bash "$HELPER" backup 2>&1); RC=$?
check "an empty BACKUP_DIR is refused, not treated as the current directory" "1" "$RC"

# --- END CASES ---
rm -rf "$TMPDIR_T"
echo "----"
echo "claude-code-new-functionality-check-helper: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
