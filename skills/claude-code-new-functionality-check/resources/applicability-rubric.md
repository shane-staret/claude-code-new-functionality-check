# Applicability rubric

How an upstream change is judged against THIS config, through two lenses: the **iteration lens** (does something the config already has need to change?) and the **new-capability lens** (what could a brand-new launch do for the whole Claude Code system?). The evaluator reads this every run; the main session uses it when merging.

## Verdicts

| Verdict | Use when | Must carry |
|---|---|---|
| **PROPOSE** | A native feature would replace, strengthen, trim, or usefully extend something here | upstream quote + URL, the local file(s) you opened, a concrete change, benefit / effort / risk, `sensitive`, what to verify first |
| **RISK-WATCH** | Upstream changed a default, a schema, a tool, a price, or removed something this config relies on | the same, with `proposed_change` = the defensive check or fix |
| **NO-ACTION** | The change is real but does not matter here — and someone might have expected it to | a one-line reason |

Everything else (bug fixes that touch nothing here) is counted in `omitted_count`, not written down. The coverage watermark is what prevents re-evaluation; `no-action.md` is a record of judgment calls, not of everything read. A **launch** (a new product, surface, extension point or way of working) is never just counted: the new-capability lens below gives every launch a disposition.

## Lenses — ask each one of every change

1. **REPLACE** — does a native feature now do what a hand-built hook, skill, or agent does? (A bundled command shadowed by a same-named skill; a native event replacing an in-script path filter; a native schedule replacing a documented-but-unwired cron.)
2. **STRENGTHEN** — does it make an existing mechanism cheaper or more robust? (Hook `if` conditions, exec-form `args`, and `async` cut spawns, and a spawn is expensive on some platforms; agent `effort` / `model` / `omitClaudeMd`; permission rules that match tool parameters.)
3. **TRIM** — does it cut standing context cost? For most configs context is the largest recurring cost: the global CLAUDE.md loaded by every session and subagent, and every skill in the skill listing. The inventory shows both sizes.
4. **NEW PRACTICE** — does it change how a session should work here? (Waiting on background work, delegating, long-running goals, review.) Only propose one when you can name the local document that should say so.
5. **RISK-WATCH** — defaults that flipped, hook input/output fields, tool removals or renames, billing and plan policy, Windows shell behaviour, the status-line JSON shape (a status-line script may parse it).
6. **NOT APPLICABLE** — Desktop / web / mobile-only, Team / Enterprise-only, Bedrock / Vertex / Foundry-only, IDE-extension-only. Say which, in one line, only if it is a notable rejection. This settles the *iteration* question only: a brand-new launch on another surface still goes to the new-capability lens, because a new surface can change how the whole system works.

## Scoring

- **benefit** H / M / L — H removes a standing cost or a real failure mode; L is tidiness.
- **effort** trivial / S / M / L / XL — count the tests the change would need.
- **risk** low / med / high — what breaks if upstream's behaviour is not what the digest implied.
- **sensitive** true when the change installs or upgrades a plugin, adds or changes a hook command, loosens a permission, touches secret handling, or changes what runs unattended.

## Quality bar

A proposal names (1) the upstream feature with its quote and URL, (2) the specific local file(s), opened and checked, (3) a concrete change. One proposal per distinct change; if one feature touches five agents the same way, that is ONE proposal listing five paths. `feature_key` is the stable upstream identifier (`agent.omitClaudeMd`, `hooks.if`, `settings.skillOverrides`, `/skill-doctor`) — the ledger dedupes on it together with the target.

## The new-capability lens (launches)

The lenses above ask whether something the config already has should change. That question misses the launches that matter most: a new product, surface, extension point, connector type, automation primitive or way of working, which no existing file would ever point to. (A design tool was once filed as "complementary to an installed plugin, no action", and two launches that brought new kinds of work into Claude Code were dropped without a word.) This lens judges every launch for what it could do for the **whole Claude Code system**: its surfaces; its extension points (plugins, skills, hooks, agents, MCP servers and connectors); and its automation, review, reporting and multi-machine operation. It does not judge the projects Claude Code works on. A launch whose benefit is only at that application layer is `no-fit`.

`claude_code_new_functionality_check.sh launches` lists the launches: every digest feature, every support-notes entry, and every new docs page. Each one gets **exactly one** disposition:

| Class | Use when | Carries |
|---|---|---|
| `new-capability` | It adds something this system has no equivalent of, and a named part of the system would use it | one PROPOSE (below) |
| `iteration` | It changes something the config already uses; the iteration lens covers it | a one-line why |
| `no-fit` | No part of the system would use it. Typical reasons: application layer only; not available on the user's plan or platform; blocked by a house constraint with no workable constrained form | the reason, specific enough that a reader could disagree |

**Ask of every launch. Be imaginative here, then strict about fit:**
1. What becomes possible for this system that was impossible or impractical before?
2. Which part of the system would change most? Name it from the inventory: a hook, skill, agent, plugin, MCP server or connector, or CLAUDE.md section.
3. Could it replace a whole hand-built subsystem, or fill a gap the system works around today?
4. What would you build differently if it had existed when the system was designed?
5. What does it combine with (an installed plugin, an MCP server or connector, a skill, another launch) to do more than either does alone?
6. Which house constraint does it touch? If one blocks it, name the constraint, and say whether a constrained form fits: a manual trigger instead of an unattended one, a local-only variant, or one pilot machine.

**Breadth** says how much of the system the launch would change:
- `system`: how the whole setup works, or most of it;
- `several`: two or more subsystems;
- `one`: a single part.

Rank new capabilities by breadth first, then by benefit ÷ effort.

**A new-capability PROPOSE** carries everything an ordinary PROPOSE carries, plus:
- `launch`: the slice's L-id. It is local to that slice, so it is never written to the ledger.
- `capability`: what becomes possible, in one or two sentences.
- `breadth`.

Two existing fields take this lens's meaning:
- `today`: where the launch would land, and how that part works now, with the file you opened;
- `proposed_change`: the adoption, starting with the smallest first step (about a day's work) and what would count as success.

**Guardrails:**
- Name the part of the system, opened and checked. "This could be useful" is not a proposal.
- No hype. A research preview, a beta or a plan limit is stated in `risk` and `verify_before_adopting`.
- One PROPOSE per new capability, best first. The evaluator never demotes a real capability to fit a number. The session keeps at most 5 a week (12 in a catch-up) and backlogs the rest.
- A digest feature feeds both lenses. When both judged the same launch, a new-capability PROPOSE replaces the iteration lens's NO-ACTION note.

## House constraints: the machine's own, not this file's

Every config has rules a proposal must not break: what may run unattended, what must stay portable, how secrets are handled, which folders are out of scope. They differ from machine to machine, so they live beside the ledger, in `house-constraints.md` (by default `~/.claude/claude-code-new-functionality-check/house-constraints.md`; the dispatch names the path). The file holds:
- a table of *constraint* → *the CLAUDE.md section that governs it*;
- any facts about the config that change how a release is judged;
- optionally, a `## What this system is for, and where it hurts` section, which gives the new-capability lens its targets.

- **When that file exists,** the evaluator reads it every run, and a proposal that would break a listed constraint is not a proposal.
- **When it does not,** judge against these general constraints, and say in `verify_before_adopting` which local rule a proposal might touch:
  - never weaken secret handling or a deny rule;
  - never make something run unattended that did not before, without saying so (`sensitive: true`);
  - prefer changes that ship with a test;
  - never propose edits to repositories the user only works in for someone else.
