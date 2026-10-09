# Example report: one real incremental sweep (2026-10-09)

This is the real output of one sweep on the author's machine. It was an incremental run covering Claude Code 2.1.279 to 2.1.295 and the support release notes through 2026-10-07. A sweep leaves three things behind, and this page shows each one:

1. **The presentation:** the fixed-shape summary printed at the end of the sweep (section 1).
2. **Proposal blocks:** one per id in `proposals.md`. Each gives the upstream quote it rests on, what the config does today, the concrete change, and what to check before adopting it (sections 2 and 3).
3. **Ledger rows:** the index rows, the coverage watermarks and the run-log line that the next sweep diffs against (section 4).

How to read it:
- **It is the author's config talking.** The files it names (`scan-secrets.sh`, `test-agent-gates.sh`, a "control-plane" settings generator) and the ids belong to the author. On your machine the ids start at `RW-0001`, and the proposals are about your files.
- **Nothing here was applied by the sweep.** Every new row is `proposed` until the user decides.
- **Two kinds of edit were made to the real output.**
  - The sweep ran shortly before the skill was renamed from release-watch, so names and paths were updated to the current ones.
  - In the one historical block (RW-0036), the user's first name was replaced by "the user".

  Nothing else was changed.

## 1. The presentation

```
New-functionality check — 2026-10-09 · incremental
Covered: digests →2026-w37 (none published since) · changelog →2.1.295 · support notes →2026-10-07 · watched pages: 3 changed · research: 1 lane (official long-form, feature-driven, theme 1 skill authoring, ecosystem), 8/8 searches
New: 10 proposals · 6 risk-watch · 13 leads logged (3 promoted after verify-lead) · 22 no-action notes        Failed/skipped lanes: none

Top proposals (benefit ÷ effort)
  RW-0046  settings  M/trivial/low  fallbackModel ["opus"] → ["sonnet"], so an Opus outage steps down to Sonnet 5.5
  RW-0048  practice  M/trivial/low  run `/doctor prompt-audit` over ~/.claude as measured evidence for the parked CLAUDE.md shrink (RW-0018)
  RW-0042  hook      M/S/med        add onFailure: "block" to the scan-secrets PreToolUse entry so a hook that cannot start fails closed   [sensitive]
  RW-0043  settings  M/S/low        narrow the Bash(python -c:*), Bash(sed:*), Bash(awk:*) allow rules: auto mode never sends narrow allow rules to the classifier   [sensitive]
  RW-0045  skill     M/S/low        make every SKILL.md frontmatter strict YAML and test it (test-completeness fails a strict parse today)
  RW-0052  agent     M/S/med        pilot the Agent tool's new effort parameter on the /code-review fan-out
  RW-0053  agent     M/S/med        --permission-mode dontAsk + a scoped --allowedTools list on the one sanctioned headless path   [sensitive]
  RW-0044  hook      M/M/med        full-text force-push guard: git -C, --force-with-lease and +main get past the 4 exact-string deny rules   [sensitive]
  RW-0056  skill     L/trivial/low  plugin-vetting: never `claude plugin install --marketplace` before the review (staged via /autoharness:learn)
  RW-0057  plugin    L/S/low        add `claude plugin validate` to the autoharness fork check   [sensitive]
By target: hooks 2 · skills 2 · agents 2 · settings/permissions 2 · CLAUDE.md/memory 0 · work practices 1 · plugins 1
Risk-watch: RW-0047 Opus 5.5 may start below the global xhigh effort — pin it under modelSettings · RW-0049 mods are on by default and can approve calls an ask rule or a PreToolUse hook would stop — add a mods step to plugin-vetting · RW-0050 the stage_skill MCP server hard-codes protocol 2024-11-05 — confirm it still connects · RW-0051 re-prove agent dispatch once on Sonnet 5.5 · RW-0054 Max plans get monthly API credits — re-check the billing text, keep overflow off · RW-0055 CLAUDE.md's headless sentence still prices fable at $10/$50; the pin is opus[1m] (Opus 5.5)
Awaiting your decision: 16 (oldest RW-0042, 0 days).
Reply: "accept RW-… RW-…", "decline RW-…: <why>", "defer RW-… until <when>", or "walk me through <target>".
Full detail: ~/.claude/claude-code-new-functionality-check/proposals.md
Housekeeping (first sweep of October): `/doctor` is interactive, so it is yours to run — it lists unused skills, plugins and MCP servers by context cost, CLAUDE.md trim candidates and slow hooks (RW-0017).
```

## 2. How to read a proposal block

| Line | Meaning |
|---|---|
| `### <id> · <target> · <title>` | the id, what part of the config it touches, and the change in one line. `[RISK]` marks a risk-watch row: something to check, which may need no change at all |
| **Status** | `proposed` until you decide; later `accepted`, `declined — <why>`, `deferred — <until>`, `applied — <evidence>` or `obsolete — <why>` |
| **Upstream** | where the change was announced, with the verbatim quote that the helper re-verified against the fetched page |
| **Today** | what the config does now, from the files the evaluator read (named at the end of the line); the main session spot-checks these claims before logging them |
| **Proposed change** | the concrete, scoped edit |
| **Benefit / effort / risk** | benefit H/M/L, effort trivial/S/M/L, risk low/med/high. **Sensitive: YES** means the row is accepted only after a walk-through, never by bare id |
| **Verify before adopting** | what the quote does not prove: the mechanism to read up on before building |
| **History** | every status change, dated |

## 3. Five new blocks from this sweep, and one finished one

### RW-0046 · settings · Re-point fallbackModel at Sonnet 5.5: model is now opus[1m] but the chain is still [opus], so an Opus outage has no step down

- **Status:** proposed (logged 2026-10-09)
- **Upstream:** support-notes 2026-09-28 · https://support.claude.com/en/articles/12138966-release-notes · docs: https://code.claude.com/docs/en/model-config#fallback-model-chains
  > Sonnet 5.5 is a faster, lower-cost complement to Claude Opus 5.5.
- **Today:** settings.json (opened) has model "opus[1m]", fallbackModel ["opus"] and autoCompactEnabled false. RW-0036 added the [opus] chain on 2026-09-19 when the pin was fable; the dated backups show the pin moved to opus on 2026-09-21 and to opus[1m] by 2026-09-27, so primary and fallback now name the same model family. The 26 agents use the rolling sonnet alias and are not touched by this. (`~/.claude/settings.json`)
- **Proposed change:** Change fallbackModel in settings.json from ["opus"] to ["sonnet"], so an overloaded or unavailable Opus steps down to Sonnet 5.5, the faster, lower-cost sibling the launch note positions beside Opus 5.5. Leave model as it is. Upstream documents the chain as tried in order when the primary is overloaded or unavailable (model-config#fallback-model-chains), so one entry is enough.
- **Benefit / effort / risk:** M / trivial / low · **Sensitive:** no
- **Verify before adopting:** Mechanism unverified: read model-config#fallback-model-chains for what happens when a fallback equals the primary (skipped, or retried?) and how long a fallback sticks. Confirm Sonnet 5.5 has the same context window as the primary: autoCompactEnabled is false here, so a smaller window would fail instead of compacting. Apply the same edit to the control-plane settings.json.
- **History:** 2026-10-09 proposed

### RW-0042 · hook · Make the secrets gate fail closed: add onFailure: block to the scan-secrets.sh PreToolUse Bash registration

- **Status:** proposed (logged 2026-10-09)
- **Upstream:** changelog 2.1.295 · https://code.claude.com/docs/en/changelog · docs: https://code.claude.com/docs/en/hooks
  > Added `onFailure: "block"` for command and HTTP hooks: a hook that can't start, times out, or exits with an unexpected code blocks the action instead of letting it through
- **Today:** settings.json registers `bash ~/.claude/hooks/scan-secrets.sh` (shell form; PreToolUse, matcher Bash, no `if`, no onFailure). The script self-filters for git commit/push and exits 2 on a match; every other path exits 0, including when jq is missing (tool_name stays empty). A hook that cannot start, times out or crashes does not block today, so the commit or push goes through unscanned. test-hook-exec-form.sh's header names this ('a broken scan-secrets.sh entry would mean commits silently go unscanned') but only checks exec-form entries statically. (`~/.claude/settings.json`, `~/.claude/hooks/tests/test-hook-exec-form.sh`)
- **Proposed change:** Add `"onFailure": "block"` to the scan-secrets.sh hook entry only (the first PreToolUse Bash group). Edit settings.json as a one-machine pilot, and carry it into the control-plane settings-fragments generator that owns the other registrations (RW-0021), because a config deploy overwrites hand edits. Do not add it to rtk, notify-sound, the reminder hooks or any Stop hook: those must stay fail-open. Write the test first: a test-*.sh wiring suite (run-all-tests.sh globs them) or an extension of test-hook-exec-form.sh asserting the scan-secrets registration carries onFailure block. Pilot a week on this Mac before the generator ships it to Windows and the Pi.
- **Benefit / effort / risk:** M / S / med · **Sensitive:** YES — accept only after a walk-through
- **Verify before adopting:** Mechanism unverified: in the hooks reference check (1) where onFailure sits (on the hook entry beside timeout and statusMessage?), (2) which exit codes count as unexpected (1? 127? are only 0 and 2 expected?), (3) the default timeout. Blast radius: the entry has no `if` (RW-0020 declined), so an unstartable hook would block EVERY Bash call until settings.json is fixed; confirm Edit still works then. onFailure does not cover the jq-missing exit 0.
- **History:** 2026-10-09 proposed

### RW-0043 · settings · Narrow the Bash(python -c:*), Bash(sed:*) and Bash(awk:*) allow rules: in auto mode a narrow allow rule runs without the classifier seeing it

- **Status:** proposed (logged 2026-10-09)
- **Upstream:** docs auto-mode-config · https://code.claude.com/docs/en/auto-mode-config · docs: https://code.claude.com/docs/en/auto-mode-config
  > a narrow rule can still let a destructive argument through without the classifier seeing it
- **Today:** settings.json permissions.allow has 27 rules including Bash(python -c:*), Bash(sed:*) and Bash(awk:*); defaultMode is auto and there is no autoMode block. Those three admit arbitrary code (python -c) and in-place edits (sed -i, awk system()) with no classifier review and no prompt. Found by the week-41 research lane, verified against the official page, grounded in settings.json. (`~/.claude/settings.json`)
- **Proposed change:** Replace Bash(python -c:*) with the specific read-only one-liners actually used (or move it to permissions.ask), and narrow Bash(sed:*) and Bash(awk:*) to forms without in-place edits, or move them to ask. Alternatively set autoMode.classifyAllShell: true in ~/.claude/settings.json so every shell command goes through the classifier, and watch latency and usage. Only tighten; never widen an allow rule.
- **Benefit / effort / risk:** M / S / low · **Sensitive:** YES — accept only after a walk-through
- **Verify before adopting:** Read auto-mode-config for which allow rules auto mode suspends (broad ones only), what classifyAllShell costs, and whether a Bash(sed:*) prefix rule covers sed -i. List what the three rules are used for before removing any.
- **History:** 2026-10-09 proposed

### RW-0045 · skill · Make every SKILL.md frontmatter strict YAML and test it: an unparseable frontmatter loads with no fields, which would drop disable-model-invocation

- **Status:** proposed (logged 2026-10-09)
- **Upstream:** docs skills · https://code.claude.com/docs/en/skills · docs: https://code.claude.com/docs/en/skills
  > If the YAML between the markers doesn't parse, the skill still loads with no fields set
- **Today:** A strict PyYAML parse of every ~/.claude/skills/*/SKILL.md frontmatter (2026-10-09) fails for test-completeness ('mapping values are not allowed here'). Claude Code's own parser reads it today (its description shows in the skill list). test-skill-invocation-flags.sh checks the six typed-only flags as text, so a broken frontmatter on one of them would pass the suite while the flag is lost. test-agent-gates.sh already parses agent frontmatter strictly (VALIDATION_PLAN rule 16). (`~/.claude/skills/test-completeness/SKILL.md`, `~/.claude/hooks/tests/test-skill-invocation-flags.sh`)
- **Proposed change:** Quote the test-completeness description so its frontmatter is strict YAML, and add a strict parse of every house SKILL.md frontmatter to test-skill-invocation-flags.sh (PyYAML, as test-agent-gates.sh does for agents; SKIP-LOUD where PyYAML is missing), so the typed-only check proves the flag survives parsing.
- **Benefit / effort / risk:** M / S / low · **Sensitive:** no
- **Verify before adopting:** This guards against a stricter parser rather than fixing a live outage: Claude Code reads the file today. Test first: the new check must fail on the current test-completeness file.
- **History:** 2026-10-09 proposed

### RW-0047 · settings · [RISK] Opus 5.5 may start at its default effort, not the global effortLevel xhigh: pin it under modelSettings (model opus[1m] now resolves to Opus 5.5)

- **Status:** proposed (logged 2026-10-09)
- **Upstream:** changelog 2.1.280 · https://code.claude.com/docs/en/changelog#2-1-280 · docs: https://code.claude.com/docs/en/model-config.md
  > Changed an effort level saved before `/effort` became per-model to no longer apply to newly released models such as Opus 5.5; they start at their default until you pick a level
- **Today:** settings.json pins model `opus[1m]` (it was `fable` until 2026-09-21; see the settings.json.bak files) with a top-level effortLevel `xhigh`. modelSettings has one entry, `claude-fable-5-1` at `high`, and none for `claude-opus-5-5`. The earlier no-action note on effort-default flips judged them moot because xhigh was pinned globally; that premise may no longer hold for the model now in use. (`~/.claude/settings.json`)
- **Proposed change:** In a fresh session run /effort and read the level Opus 5.5 starts at. If it is not the xhigh you intend, add a `claude-opus-5-5` entry with effortLevel xhigh under modelSettings in settings.json (same shape as the existing fable entry), or pick the level once in /effort so it is saved per model. Carry the line into the control-plane settings generator, or a config ZIP built there will drop it.
- **Benefit / effort / risk:** M / trivial / low · **Sensitive:** no
- **Verify before adopting:** Mechanism unverified: whether the top-level effortLevel is the 'saved before per-model' value the note means; what level Opus 5.5 starts at; that modelSettings takes the full model ID as its key (the fable entry does). Read model-config.md.
- **History:** 2026-10-09 proposed

### A finished one: RW-0036, from the first backfill three weeks earlier

This is the block RW-0046 builds on. It shows the whole lifecycle: proposed, then accepted with a narrower scope than proposed, then applied with its evidence, then a later note. Three weeks on, this sweep noticed that a model change had left the chain pointing at the primary itself.

### RW-0036 · settings · Configure a fallbackModel chain so sessions degrade gracefully instead of failing when the pinned fable model is unavailable

- **Status:** applied — fallbackModel: [opus] in settings.json; JSON valid, diff checked, 17/17 suites (decided 2026-09-19)
- **Upstream:** whats-new 2026-w24 · https://code.claude.com/docs/en/whats-new/2026-w24 · docs: https://code.claude.com/docs/en/model-config#fallback-model-chains
  > configures up to three fallback models tried in order when the primary is overloaded or unavailable, and `--fallback-model` now applies to interactive sessions too
- **Today:** settings.json pins model to fable plus a modelSettings override for claude-fable-5-1's effortLevel (confirmed), and sets no fallbackModel — so an overloaded/unavailable primary has no configured degrade path today. (`~/.claude/settings.json`)
- **Proposed change:** Add a fallbackModel list (up to three models) to settings.json so interactive sessions fall back automatically instead of failing outright when the pinned model is overloaded or unavailable.
- **Benefit / effort / risk:** M / S / low · **Sensitive:** no
- **Verify before adopting:** Pick fallback model names appropriate to the user's actual plan/cost tolerance from current docs — none is evidenced in this config's files.
- **Note (2026-09-21):** the user switched the default model to opus (settings model: opus). fallbackModel is still [opus], so there is no longer a different model to fall back to; worth revisiting only if they want a fallback again.
- **History:** 2026-09-19 proposed · 2026-09-19 accepted — with the chain [opus] only: never drop below Opus; if Opus is unavailable too the turn fails as it does today · 2026-09-19 applied — fallbackModel: [opus] in settings.json; JSON valid, diff checked, 17/17 suites

## 4. What the ledger kept

**Proposal index**, the rows this sweep added to `ledger.md`. `ledger-add` writes them; nobody types them by hand.

| ID | status | target | feature_key | title | upstream | logged | decided |
|---|---|---|---|---|---|---|---|
| RW-0042 | proposed | hook | hooks.onFailure | Make the secrets gate fail closed: add onFailure: block to the scan-secrets.sh PreToolUse Bash registration | 2.1.295 | 2026-10-09 | |
| RW-0043 | proposed | settings | auto-mode.classifyAllShell | Narrow the Bash(python -c:*), Bash(sed:*) and Bash(awk:*) allow rules: in auto mode a narrow allow rule runs without the classifier seeing it | auto-mode-config | 2026-10-09 | |
| RW-0044 | proposed | hook | permissions.bash-rule-limits.pretooluse | Guard force pushes to main/master on the full command text: the four exact-string deny rules miss git -C, --force-with-lease and +refspec forms | auto-mode-config | 2026-10-09 | |
| RW-0045 | proposed | skill | skills.frontmatter.yaml-parse-failure | Make every SKILL.md frontmatter strict YAML and test it: an unparseable frontmatter loads with no fields, which would drop disable-model-invocation | skills | 2026-10-09 | |
| RW-0046 | proposed | settings | model.claude-sonnet-5-5 | Re-point fallbackModel at Sonnet 5.5: model is now opus[1m] but the chain is still [opus], so an Opus outage has no step down | 2026-09-28 | 2026-10-09 | |
| RW-0047 | proposed | settings | settings.modelSettings.effortLevel | [RISK] Opus 5.5 may start at its default effort, not the global effortLevel xhigh: pin it under modelSettings (model opus[1m] now resolves to Opus 5.5) | 2.1.280 | 2026-10-09 | |
| RW-0048 | proposed | work-practice | /doctor prompt-audit | Run `/doctor prompt-audit` over ~/.claude (stale paths, contradictions, older-model prompt patterns) as evidence for the parked CLAUDE.md shrink | 2.1.283 | 2026-10-09 | |
| RW-0049 | proposed | skill | plugins.claude-mods | [RISK] Add a 'mods' step to the plugin-vetting skill: Claude Mods let plugins modify deeper behavior, and the official plugins here keep updating | 2.1.287 | 2026-10-09 | |
| RW-0050 | proposed | plugin | mcp.stdio-protocol-negotiation | [RISK] Check that the autoharness stage_skill MCP server (hand-rolled, fixed protocol 2024-11-05) still connects now that stdio servers negotiate 2026-07-28 | 2.1.292 | 2026-10-09 | |
| RW-0051 | proposed | agent | models.sonnet-5-5-default | [RISK] Re-prove agent dispatch once on Sonnet 5.5: all 26 agents pin `sonnet`, last proven 2026-09-21, before Sonnet 5.5 became the default Sonnet | 2.1.284 | 2026-10-09 | |
| RW-0052 | proposed | agent | tools.Agent.effort | Pilot the Agent tool's new effort parameter on the /code-review fan-out: state the effort of the five specialists in code-reviewer.md Step 2 | 2.1.292 | 2026-10-09 | |
| RW-0053 | proposed | agent | cli.--permission-mode-dontAsk | Add --permission-mode dontAsk and a scoped --allowedTools list to the one sanctioned headless path so unattended reviews deny instead of classify | 2026-10-09 | 2026-10-09 | |
| RW-0054 | proposed | claude-md | billing.monthly-api-credits | [RISK] Max plans now get monthly API credits claimed via a linked Console org: check the Headless billing text and keep usage-credit overflow off | 2026-10-07 | 2026-10-09 | |
| RW-0055 | proposed | claude-md | model-config.opus-5-5-default | [RISK] Refresh the Headless-policy sentence in CLAUDE.md: it prices a pinned `fable` at $10/$50 per MTok, but settings now pin opus[1m] (Opus 5.5, $4/$20) | 2.1.280 | 2026-10-09 | |
| RW-0056 | proposed | skill | cli.plugin-install.--marketplace | plugin-vetting: warn that `claude plugin install --marketplace <source>` adds a marketplace and installs in one step, before the code is read | 2.1.292 | 2026-10-09 | |
| RW-0057 | proposed | plugin | cli.plugin-validate | Add `claude plugin validate` to the autoharness fork check: four shell-form hook commands leave ${CLAUDE_PLUGIN_ROOT} unquoted, plus a stdio MCP entry | 2.1.281 | 2026-10-09 | |

**Coverage**, the watermarks the next sweep starts from. Each source advances only when it succeeded.

| source | covered through | last success (UTC) | consecutive failures |
|---|---|---|---|
| whats-new digests | 2026-w37 (no digest published after w37 as of 2026-10-09) | 2026-10-09T18:05:41Z | 0 |
| changelog | 2.1.295 | 2026-10-09T18:05:41Z | 0 |
| support release notes | 2026-10-07 | 2026-10-09T18:05:41Z | 0 |
| docs index | snapshot 2026-10-09 | 2026-10-09T18:05:41Z | 0 |
| best practices | snapshot 2026-10-09 | 2026-10-09T18:05:41Z | 0 |
| plugin marketplace | snapshot 2026-10-09 | 2026-10-09T18:05:41Z | 0 |
| npm latest (canary) | 2.1.295 | 2026-10-09T18:05:41Z | 0 |
| tracked issues | checked 2026-10-09 (45645: closed as duplicate; no new evidence; workaround kept — RW-0007) | 2026-10-09T18:05:41Z | 0 |
| research: official long-form | posts through 2026-10-08 (two posts listed but unread: see leads.md) | 2026-10-09T18:05:41Z | 0 |
| research: rotating theme | theme 1 skill authoring (week 41) | 2026-10-09T18:05:41Z | 0 |

**Run log**, one line per sweep:

```
- 2026-10-09T18:05:41Z incremental · sources 32/32 ok (10 fetched, 22 cached; no new digest since w37) · evaluators 3/3 valid · quotes 14/14 verified · research 1 lane 8/8 searches 8/8 fetches, 16 leads (12 claimed verified; 5 quotes re-verified by verify-lead, 3 promoted) · +10 proposals +6 risk-watch (RW-0042–RW-0057; one cross-lane duplicate merged) +13 leads +22 no-action notes · currency check: no candidate older than 4 weeks · failed lanes: none · every agent handed back through the new SubagentHandback call, which save-result did not read; it was taught to, test-first (helper suite 374/374)
```

Note the last clause of that line: the sweep hit a change in Claude Code itself (subagents began handing back their reply through a new tool call), and the helper was fixed test-first before anything was logged.

## 5. What you do with a report like this

1. **Triage by id**, in the conversation, whenever it suits you:
   - `accept RW-0046`;
   - `decline RW-0048: not worth a session`;
   - `defer RW-0051 until the next fresh session`;
   - `walk me through hooks`.

   Sensitive rows (RW-0042, RW-0043, RW-0044, RW-0053 and RW-0057 here) are accepted only after a walk-through. Before walking you through a row, the session re-reads the current reference page for its mechanism, because a verified quote proves that a feature exists, not how it behaves. A wrong premise gets a dated `Correction` line in the block.
2. **Each decision is recorded** with the helper. The session runs `snapshot`, then `ledger-status`, then `ledger-check`:

   ```bash
   bash ~/.claude/skills/claude-code-new-functionality-check/claude_code_new_functionality_check.sh ledger-status RW-0046 accepted
   ```

   `declined` needs the why, `deferred` the until, and `applied` the evidence.
3. **Implementing is a separate task.** Say "implement RW-0046". Claude then:
   - reads the block in `proposals.md`;
   - settles the "Verify before adopting" items first;
   - makes the change under your normal review and tests;
   - records `ledger-status RW-0046 applied "<what changed and how it was verified>"`. RW-0036 above shows the result.

   The sweep itself never applies anything.
