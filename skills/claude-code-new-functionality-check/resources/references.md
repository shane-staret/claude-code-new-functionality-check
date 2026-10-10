# References — claude-code-new-functionality-check

Where each rule in this skill comes from. Primary sources first; house decisions are marked as such.

| Rule in the skill | Source |
|---|---|
| What's New is a weekly digest of *notable* features, and "for every bug fix and minor improvement, see the changelog" → the changelog is a core source, not an extra | Claude Code docs, "What's new" — https://code.claude.com/docs/en/whats-new |
| The docs serve raw markdown at `.md` URLs, and `llms.txt` indexes every page → deterministic fetching and docs-index diffing | Claude Code docs index — https://code.claude.com/docs/llms.txt |
| `UserPromptSubmit` stdout is injected as context; command hooks there time out at 30 s; hook input carries `agent_id` only inside a subagent; no CLI-version variable is exposed → a time-based, notice-only trigger with a subagent skip | Hooks reference — https://code.claude.com/docs/en/hooks |
| A subagent's `tools` field is an allowlist ("can't edit files, write files, or use any MCP tools"); `omitClaudeMd` is a supported agent key; agent files are reloaded from a watched directory → two agents with disjoint capabilities | Subagents reference — https://code.claude.com/docs/en/sub-agents |
| A personal skill replaces a bundled command of the same name; description + `when_to_use` are truncated in the skill listing → a trigger-only description under 500 characters | Skills reference — https://code.claude.com/docs/en/skills |
| "Target under 200 lines per CLAUDE.md"; imports still load at launch → the global rule is compact and the procedure lives here | Memory reference — https://code.claude.com/docs/en/memory |
| No hook, agent, or skill starts a headless session; notices carry deferred work to the live session | author's house policy: a headless session runs unattended and bills separately, so a notice the user's session acts on is the safer default |
| Classify / wrap / surface / account for external I/O; per-attempt timeout, overall deadline, transient classes only, Retry-After, a per-item ledger that decides the exit code | author's retry standard; AWS Builders' Library, "Timeouts, retries, and backoff with jitter" — https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/ |
| Tests first; stale tests are updated, never weakened; the package's suites live under `hooks/tests/` | superpowers:test-driven-development; author's testing standard |
| SKILL.md + `resources/` with references, testing, worked example; trigger-only description with negative scope; no `archive/` dir | author's skill-authoring standard; superpowers:writing-skills (description rules, baseline-first testing) |
| The hook owns the state format and exposes `--status` / `--write-state` to its skill | author's house convention: one owner per state file, so a hook and its skill can never disagree |
| Sequential ids, never reused; statuses move only on the user's explicit word; every change surfaced | author's house convention for decision ledgers |
| Per-machine facts (house constraints, tracked issues, denylist, backup target) live beside the ledger, never in the skill folder | house decision, 2026-10-09, when the skill was published: what is tested is what ships, and an update can never overwrite a machine's own lists |
| `save-result` also reads a reply handed back through the `SubagentHandback` tool call | observed 2026-10-09: every agent in an incremental sweep returned its JSON that way; the old transcript reader found only closing prose |
| Web content and agent output are data; researcher has no local read; verification is deterministic (`verify-quote`, `verify-lead`); agendas pass `scrub-check` | house decision, 2026-09-19, after an independent design review (prompt injection and outbound-privacy findings) |
| A second lens judges every LAUNCH for what it could do for the whole Claude Code system; every launch gets a disposition; launches are listed by the helper (`launches`), and only a validated, complete lane is recorded as seen | house decision, 2026-10-09. The evidence was the ledger itself. The iteration lens filed a design tool's arrival in Claude Code as "complementary to an installed plugin, no action". Two launches that brought new kinds of work into Claude Code (designs, decks and docs in any conversation, and a directory for publishing plugins) sat in a swept slice and were counted among 80 "omitted" items without a word. The rubric's "not applicable" lens and its rule that other platforms' news is only counted had discarded them by design. |
| Launch sources: digest features (each digest states its own feature count, so drift is checkable), support-notes entries (`<h3>` dates, a bold title per entry), new docs-index pages | the What's New digests — https://code.claude.com/docs/en/whats-new ; the Claude release notes — https://support.claude.com/en/articles/12138966-release-notes ; the docs index — https://code.claude.com/docs/llms.txt (formats checked against the cached pages, 2026-10-09) |
| The lens judges the system layer (surfaces, extension points, automation, review, reporting, multi-machine operation), never the projects Claude Code works on | house decision, 2026-10-09: "this is at the system layer of Claude Code. Not at the application layer of what it's actually working on" |
| The lens is dispatched with the most capable model; breadth (`system` / `several` / `one`) ranks new capabilities before benefit ÷ effort | house style: imagining what a launch makes possible is the judgment this lens exists for, and a change to how the whole system works outweighs a local saving |
| The inventory names MCP servers, connectors, plugins and marketplaces, but prints no value: only an allowlist of fields | house decision, 2026-10-09: the lens needs the whole system layer, and secrets hygiene forbids values (MCP entries carry URLs with keys, headers, commands and env) |

## Rules added after the first real run (2026-09-19) — house style, with their evidence

| Rule | Evidence |
|---|---|
| `scrub-check` fails closed without a seeded denylist; a lock with no timestamp is never treated as infinitely old; a malformed ledger id is a reported problem, not a crash | independent read-only review of the build, 2026-09-19 (each finding reproduced as a failing suite case first); principle: fail securely — OWASP, https://owasp.org/www-community/Fail_securely |
| Replies are saved with `save-result` from the agent's transcript, never pasted | observed in the first backfill: notification text is HTML-escaped by the harness, and one 30 KB reply was split in two by the output-token limit |
| Length caps: stated in the agent files, soft (`OVERLONG`, up to 2x) at validation, hard at `ledger-add` | observed: 4 of 13 lanes were rejected over caps the agents had never been told; validate input where it is read, enforce limits where it is written — OWASP Input Validation Cheat Sheet, https://cheatsheetseries.owasp.org/cheatsheets/Input_Validation_Cheat_Sheet.html |
| The main session greps the file behind every `today` claim it promotes | observed: a verified quote sat beside a wrong local claim (a command described as allow-listed is denied in `settings.json`) |
| `verify-lead` reuses a copy fetched within the hour | observed: one fetch per quote against the same docs page hit the site's rate limit (about 75 s per lead with `Retry-After` honored) |
| A proposal's MECHANISM is checked against the current reference page before the user is walked through it; a wrong premise gets a dated Correction line | observed in the first triage walk (2026-09-19): 6 of 39 rows rested on a guessed mechanism — e.g. "bypass mode ignores deny rules" (docs: "Deny rules block in every mode, including `bypassPermissions`"), "an allow rule could override these deny rules" (docs: it cannot), `continueOnBlock` proposed for a command hook (it is a prompt-hook field) |
| One shared normalizer for every quote verifier | review finding: the shell and python normalizers disagreed on form feeds and non-breaking spaces |

## Deliberate deviations

- **The 5-rep wording micro-tests from superpowers:writing-skills were not run.** One application scenario and one pressure scenario were run baseline-first instead. The author's skill-authoring standard sets the floor ("a fresh-context read-through") and wins where the two conflict; the pressure baseline showed no failure to bulletproof against.
- **Both agents set `omitClaudeMd: true`.** Neither writes code, and a read-only evaluator does not need the user's whole global rule file; the per-machine `house-constraints.md` names the sections that matter. On a CLI older than 2.1.271 the key is ignored and the agents simply load CLAUDE.md as before.
- **The hook handles `--status` / `--write-state` BEFORE its opt-out:** a manual sweep on a machine with notices switched off must still be recorded.
- **`curl --fail` is not used.** Measured on macOS, it exits 56 on a plain 404 — a "network" code that would be retried. The helper classifies by HTTP status first.
- **Decision record.** This table and the author's session docs carry the design decisions; there is no separate ADR log in the package.
