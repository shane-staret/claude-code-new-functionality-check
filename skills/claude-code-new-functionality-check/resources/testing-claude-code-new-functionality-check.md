# Testing a sweep, and testing changes to the new-functionality check

How to verify work done under this skill before calling it done. Runner evidence, not "should pass".

## Automated — run these and show the output

The four suites ship with the package and are hermetic: they find the helper, hook and agents relative to themselves, so the same commands work under `~/.claude/hooks/tests/` and from a clone (`hooks/tests/`).

1. **Hook suite**: `bash ~/.claude/hooks/tests/test-claude-code-new-functionality-check-reminder.sh`. Offline; the clock is injected (`NEW_FUNCTIONALITY_CHECK_NOW`), so nothing sleeps. It covers:
   - dormant, never-run, due and fresh;
   - the interval and renotice windows, quiet trees (none by default), the opt-out;
   - every headless guard, the subagent skip, corrupt and future-dated state;
   - both modes, argument sanitizing, and exit 0 on every hook path.
2. **Helper suite**: `bash ~/.claude/hooks/tests/test-claude-code-new-functionality-check-helper.sh`. Offline; every source is a `file://` fixture generated inside the sandbox, and the transient-failure path uses a refused localhost port. Case 0 is `bash -n` on the helper. `save-result` is covered for split replies, pasted text and SubagentHandback calls: the last non-blank handback wins, and a blank one falls back to the assistant's text.
3. **Package suite**: `bash ~/.claude/hooks/tests/test-claude-code-new-functionality-check-package.sh`. It covers:
   - the two agents' `tools:` lines, exactly (a missing line would inherit every tool);
   - the skill's shape and resources table;
   - that the source registry documents every URL the helper fetches (at least 10 must be found);
   - that every validator length cap is a number and is stated in the agent that writes the field;
   - negative controls on fixtures, which prove both comparisons fail when their extraction finds nothing;
   - that the installer, README and LICENSE ship, and that every script parses.
4. **Installer suite**: `bash ~/.claude/hooks/tests/test-claude-code-new-functionality-check-install.sh`. It runs against a temporary HOME and covers:
   - the dry run, and `--help` describing every option the parser accepts;
   - the copy with backups outside `skills/` and `agents/`, a fresh backup folder for each run (even two in one second), and a failure part-way that names the backup folder;
   - a script whose executable bit was lost, repaired and reported as a mode fix;
   - the in-place no-op, and an unwritable target (exit 2);
   - an idempotent `--register-reminder` that validates the JSON, refuses an empty or wrongly shaped `settings.json` before any backup, and refuses a target path it cannot quote in the hook command;
   - writes through a symlinked `settings.json` (absolute, relative, or a chain) without replacing a link, and refuses a link loop;
   - file modes: `settings.json` keeps its mode, a new one is 0600, and no temporary copy is readable more widely than the original;
   - `--opt-in`, with a 0700 ledger folder and a 0600 denylist;
   - an exported `CDPATH` and a target path holding a newline;
   - warnings on stderr, and never deleting.

   Without jq, the cases that write `settings.json` are reported as `SKIP-LOUD`; the target-path quoting check still runs.

A machine may add its own wiring check (for example, whether the hook is registered in its real `settings.json` after a config deploy); that check reads private config and does not ship.

## After a sweep — check the run, not just the tools

5. `claude_code_new_functionality_check.sh ledger-check` prints `ledger-check: ok (N proposals)`.
6. Every PROPOSE / RISK-WATCH in this sweep passed `verify-quote`; every promoted lead passed `verify-lead`. The run-log line carries both counts.
7. `bash ~/.claude/hooks/claude-code-new-functionality-check-reminder.sh --status` prints `FRESH` with today's timestamp — or, when a core source failed, still prints `DUE`, and the presentation names the failed source.
8. The presentation followed the recipe and ended with the open-proposal count.
9. No file under `~/.claude/skills/` or `~/.claude/agents/` gained fetched text (a quoted headless-invocation example from a page would trip any config test that forbids that form).

## Changing the hook or the helper

Test first, one behaviour at a time: add the case, watch it fail for the right reason, write the least code that passes, rerun the whole suite. A case that asserts behaviour you changed on purpose is stale — update it and say so; never weaken a case to get green. New network code goes through `http_get`, and any new classification branch gets a `_classify` case.

## Testing the skill text itself

After the first real backfill a third fresh-context check was run: an agent with only SKILL.md answered eleven operational questions (order of work under a notice, a failed core source, saving a reply, `OVERLONG`, a missing denylist, a self-verified blog lead, an unchecked `today` claim, a refused `ledger-add`, a passing "sounds great", the closing commands, an instruction inside a fetched file). All eleven were answered correctly from SKILL.md alone; the five gaps it named (stale locks, the denylist's format, a `today` claim that fails its check, what a failed core source does to the rest of the sweep, how a lead can return) were closed the same day. Re-run that exercise after any substantial edit to SKILL.md.

The skill was written against two fresh-context baseline scenarios (no skill loaded): an application scenario ("what changed since March, and what should change in my config?") and a pressure scenario ("that one sounds great", said in passing). The baseline failed the first — two-page sourcing, no persistence, no ids, nothing grounded in the real config — and passed the second, which is why the status rule is one line and the sourcing, capture, and grounding steps are the bulk of `SKILL.md`. After a substantial rewrite, rerun both scenarios with the skill loaded.
