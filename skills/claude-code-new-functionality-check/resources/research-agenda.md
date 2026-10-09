# Research agenda

How the main session writes the agenda a `claude-code-new-functionality-check-researcher` works. The agenda is the ONLY thing the researcher is told, and its search queries leave the machine, so it is written in public technical terms. The **whole dispatch text** (agenda plus any constraints you add) is saved to a file and must pass `claude_code_new_functionality_check.sh scrub-check <file>` before any dispatch. Only general constraints go to the researcher, never the per-machine `house-constraints.md`.

## Lanes

| Lane | Weekly sweep | Backfill |
|---|---|---|
| **Official long-form** — Anthropic engineering blog and Claude blog (Claude Code category): posts newer than the covered date | always | one researcher |
| **Feature-driven** — for the most consequential `feature_key`s this sweep: real-world usage, pitfalls, migration notes | up to 3 questions | folded into each themed researcher |
| **Rotating theme** — ONE theme per sweep, chosen by ISO week number modulo 8 (`date +%V`), so every theme is revisited every two months without any bookkeeping | 1 theme | all 8, split across three researchers |
| **Ecosystem** — releases of installed plugins (`sources.md`), new official-marketplace plugins named by `watch-diff` | when `watch-diff` or a plugin release shows something | one pass |

Workaround retirement is NOT a research lane: it is deterministic (`tracked-issues`, `issue-status`, `issue-evidence`) and judged by the evaluator.

## The eight themes

0. Hook pipelines — Stop-hook block-and-continue, notice hooks, spawn cost, new hook events and fields
1. Skill authoring — frontmatter, discovery, context cost of the skill listing, testing skills
2. Subagent ensembles and orchestration — dispatch, nesting, models and effort, background work, review fan-out
3. Multi-machine configuration — plugins and marketplaces versus archive deploys, settings translation
4. Context cost — CLAUDE.md size, rules with path scoping, imports, memory, per-subagent instruction loading
5. Permissions and auto mode — deny/ask rules, the classifier, sandboxing, unattended runs
6. Secrets and supply chain — secret scanning, plugin trust, npm and marketplace integrity
7. Session continuity — memory, session docs, goals, loops, scheduled and background sessions

## Writing the agenda

- Public technical terms only: product names, setting names, flags, error text. **Never** a person, company, client, engagement, or project name; never a path, hostname, username, or email; never text copied from the config. Describe a local mechanism generically ("a Stop hook that blocks once and continues") rather than by its file name.
- One question per line, each answerable by a page a stranger could have written.
- State the budget in the dispatch (8 searches + 8 fetches per researcher) and the covered date for the long-form lane.
- Save the agenda to `cache/agenda-<lane>.txt`, run `scrub-check`, and dispatch only on `scrub-check: clean`. A hit means rewrite the line, not delete the denylist entry.

## After the researcher returns

`validate-candidates researcher <file>` → for every lead worth keeping, find the official page that says the same thing and run `verify-lead <official-url> "<quote>"` → verified leads are grounded against the inventory (by the main session, or one evaluator dispatch for a large batch) and enter the normal candidate path → the rest are appended to `leads.md` with the date and what would verify them. `leads.md` is never read back by a sweep.
