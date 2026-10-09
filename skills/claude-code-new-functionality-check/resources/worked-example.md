# Worked example — the first backfill (2026-09-19)

A real sweep, end to end, on the machine that built this skill. Upstream text is paraphrased here on purpose: fetched text never lives under `~/.claude/skills/` (config tests may scan that tree), and private names are scrubbed. Numbers are the real ones. For what a finished sweep's output looks like, see `example-report.md`.

## 0. Why it ran

The hook printed its **never-run** notice (ledger directory present, no `ledger.md`). That variant means *ask before a backfill*. The user was asked, and chose "full backfill now" and "research here, hardened". An incremental sweep needs no such question; a backfill always does.

## 1. Lock, fetch, slice, inventory (steps 1–4)

| Command | Result |
|---|---|
| `claude_code_new_functionality_check.sh lock` | `lock: taken` |
| `claude_code_new_functionality_check.sh fetch` | 32 of 32 sources ok in 7 s — index, 24 digests (week 31 was never published), changelog (newest 2.1.278, canary ok), docs index, best practices, marketplace, npm latest, support notes rendered to text |
| `changelog-since <v> <until> --no-fixed` ×4 | four slices of roughly 65 KB (2.1.83–150, 151–220, 221–250, 251–latest) |
| `watch-diff` | three **baselines** — first sight is never reported as "no change" |
| `issue-status 45645` + `issue-evidence 45645` | closed as *duplicate* (not fixed); two changelog fixes mention the keywords |
| `inventory > cache/inventory.md` | 120 lines: 23 hook registrations, 24 agents, 34 skills, settings key names, CLAUDE.md size |

## 2. Dispatch (steps 5 and 7)

Nine `claude-code-new-functionality-check-evaluator` agents (4 digest batches of six weeks, 4 changelog slices, 1 for support notes + tracked issue + watch-diff) and four `claude-code-new-functionality-check-researcher` agents (hooks and skills · subagents and multi-machine config · context cost, permissions and continuity · official long-form and plugin ecosystem). Each agenda passed `scrub-check` first; each researcher had 8 searches + 8 fetches and used 31 of 32 searches between them. Changelog evaluators were told which features the digests highlight — "the digest evaluators own those" — so duplicates were cut at the source, not after.

## 3. Saving and validating replies

Replies were saved from the agents' **transcripts** (`save-result <out.json> <output-file>`), not from the notification text: the harness HTML-escapes instruction-shaped output, and one 30 KB reply had hit the output-token limit and continued mid-word in a second message — the transcript pieces rejoin cleanly, a pasted notification would not have.

`validate-candidates` then rejected 4 of 13 files, each for one field a few characters over a length cap **the agent files had never stated**. The gate was wrong, not the agents, so it was fixed test-first rather than waved through: every cap is now printed in both agent files (the package suite checks that), validation flags a field up to twice its cap as `OVERLONG` (reword it while curating) instead of discarding the lane, and `ledger-add` became the hard write gate. After that: 13 of 13 valid, 4 fields flagged.

## 4. Verification

- **Quotes:** `verify-candidates` found 100 of 101 actionable quotes verbatim in the fetched text. The one miss had a full stop the source does not have — it was dropped, which is the point of the check.
- **Leads:** researchers claimed 45 leads verified; `verify-lead` re-fetched each official page itself and confirmed 35. The other 10 stayed leads. Two practical lessons are now in the helper and the skill: several leads cite the same docs page, and re-fetching it once per quote tripped the site's rate limit (a copy fetched within the hour is now reused); and a quote with backticks verifies against the page's `.md` URL when the rendered HTML has lost them.
- **Instruction-shaped text:** all four digest evaluators independently flagged the same banner at the top of every digest page — a blockquote telling the reader to fetch the docs index first. Nobody followed it; it is logged once in `no-action.md`.

## 5. Currency check (step 8)

Grepping the full changelog for each promoted `feature_key` beside "removed / reverted / no longer" retired four candidates: a keybinding setting that a later release says no longer has any effect, an output-size setting removed together with the tool it served, a cache-TTL setting scoped to API-key billing (this config is subscription-billed), and a hook on a tool that newer models are no longer offered. Two evaluators had also reached opposite verdicts on one setting; a grep of every `SKILL.md` settled it with local evidence.

## 6. Curation and capture (step 9)

100 verified actionable candidates became **24 proposals + 15 risk-watch rows**: one command-name collision had been reported by five different evaluators and became one row citing all five releases. 22 further candidates went to `backlog.md` un-id'd, 32 verified-but-ungrounded leads beside them, 34 unverified leads to the write-only `leads.md`, 55 notable rejections to `no-action.md`.

Spot-checking `today` claims caught an error before it was logged: an evaluator wrote that a Bash edit command was **allow**-listed here; `settings.json` actually **denies** it. The quote was genuine — the local claim was not. The helper verifies quotes; grounding is still the main session's job.

```
snapshot                      -> nothing to snapshot (first write)
ledger-add cache/curated.json -> RW-0001 … RW-0039
(by hand) coverage rows, one run-log line
ledger-check                  -> ok (39 proposals)
watch-commit                  -> three snapshots promoted
snapshot                      -> archive/<UTC>/ (so the next ledger-check can prove nothing vanished)
```

## 7. Present, record, release (steps 10–11)

Presented in the recipe's shape: the covered line, the counts, at most 15 top proposals with `[sensitive]` marks, the risk-watch rows, the open count, and the reply grammar. Then `claude-code-new-functionality-check-reminder.sh --write-state "2026-w37 / v2.1.278 / 2026-09-15"` (every core source had succeeded), `unlock`, and `--status` answered `FRESH`. No status moved and nothing was applied.

## What it cost, and what a weekly sweep looks like

The thirteen agents used roughly 2.3 million subagent tokens (evaluators 185–260 K each, researchers 90–130 K) and the slowest lane took about 80 minutes. A weekly sweep is a different animal: one new digest plus a changelog tail of 8–15 versions, one evaluator, one researcher working the official long-form lane, the tracked issues and ONE rotating theme — a few hundred thousand tokens, and nothing at all to evaluate when the index has no new week.
