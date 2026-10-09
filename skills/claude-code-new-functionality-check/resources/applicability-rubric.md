# Applicability rubric

How an upstream change is judged against THIS config. The evaluator reads this every run; the main session uses it when merging.

## Verdicts

| Verdict | Use when | Must carry |
|---|---|---|
| **PROPOSE** | A native feature would replace, strengthen, trim, or usefully extend something here | upstream quote + URL, the local file(s) you opened, a concrete change, benefit / effort / risk, `sensitive`, what to verify first |
| **RISK-WATCH** | Upstream changed a default, a schema, a tool, a price, or removed something this config relies on | the same, with `proposed_change` = the defensive check or fix |
| **NO-ACTION** | The change is real but does not matter here — and someone might have expected it to | a one-line reason |

Everything else (bug fixes that touch nothing here, other platforms' news) is counted in `omitted_count`, not written down. The coverage watermark is what prevents re-evaluation; `no-action.md` is a record of judgment calls, not of everything read.

## Lenses — ask each one of every change

1. **REPLACE** — does a native feature now do what a hand-built hook, skill, or agent does? (A bundled command shadowed by a same-named skill; a native event replacing an in-script path filter; a native schedule replacing a documented-but-unwired cron.)
2. **STRENGTHEN** — does it make an existing mechanism cheaper or more robust? (Hook `if` conditions, exec-form `args`, and `async` cut spawns, and a spawn is expensive on some platforms; agent `effort` / `model` / `omitClaudeMd`; permission rules that match tool parameters.)
3. **TRIM** — does it cut standing context cost? For most configs context is the largest recurring cost: the global CLAUDE.md loaded by every session and subagent, and every skill in the skill listing. The inventory shows both sizes.
4. **NEW PRACTICE** — does it change how a session should work here? (Waiting on background work, delegating, long-running goals, review.) Only propose one when you can name the local document that should say so.
5. **RISK-WATCH** — defaults that flipped, hook input/output fields, tool removals or renames, billing and plan policy, Windows shell behaviour, the status-line JSON shape (a status-line script may parse it).
6. **NOT APPLICABLE** — Desktop / web / mobile-only, Team / Enterprise-only, Bedrock / Vertex / Foundry-only, IDE-extension-only. Say which, in one line, only if it is a notable rejection.

## Scoring

- **benefit** H / M / L — H removes a standing cost or a real failure mode; L is tidiness.
- **effort** trivial / S / M / L / XL — count the tests the change would need.
- **risk** low / med / high — what breaks if upstream's behaviour is not what the digest implied.
- **sensitive** true when the change installs or upgrades a plugin, adds or changes a hook command, loosens a permission, touches secret handling, or changes what runs unattended.

## Quality bar

A proposal names (1) the upstream feature with its quote and URL, (2) the specific local file(s), opened and checked, (3) a concrete change. One proposal per distinct change; if one feature touches five agents the same way, that is ONE proposal listing five paths. `feature_key` is the stable upstream identifier (`agent.omitClaudeMd`, `hooks.if`, `settings.skillOverrides`, `/skill-doctor`) — the ledger dedupes on it together with the target.

## House constraints: the machine's own, not this file's

Every config has rules a proposal must not break: what may run unattended, what must stay portable, how secrets are handled, which folders are out of scope. They differ from machine to machine, so they live beside the ledger, in `~/.claude/claude-code-new-functionality-check/house-constraints.md` (a table of *constraint* → *the CLAUDE.md section that governs it*, plus any facts about the config that change how a release is judged).

- **When that file exists,** the evaluator reads it every run, and a proposal that would break a listed constraint is not a proposal.
- **When it does not,** judge against these general constraints, and say in `verify_before_adopting` which local rule a proposal might touch:
  - never weaken secret handling or a deny rule;
  - never make something run unattended that did not before, without saying so (`sensitive: true`);
  - prefer changes that ship with a test;
  - never propose edits to repositories the user only works in for someone else.
