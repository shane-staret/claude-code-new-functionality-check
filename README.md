# Claude Code New-Functionality Check

A [Claude Code](https://code.claude.com/docs) skill that keeps **your** Claude Code setup current.

Claude Code ships new versions almost daily. Your skills, hooks, agents, settings and `CLAUDE.md` were written against whatever existed the day you wrote them, so they quietly fall behind. Once a week this skill:
1. reads what shipped upstream: the What's New digests, the changelog, the support release notes and changes to the docs, plus a small, budgeted web-research pass;
2. judges every change against your config as it actually is;
3. judges every **brand-new launch** for what it could do for your whole Claude Code system, beyond tweaks to the files you already have. A launch is a new product, surface, extension point or way of working, such as a design tool you can drive from Claude Code or a new place to publish plugins;
4. logs concrete improvement proposals with stable ids (`RW-0001`, `RW-0002`, …) in a ledger on your machine.

You then accept, decline or defer each proposal by id. **It never changes your config by itself.**

- **What a finished sweep looks like:** [example-report.md](https://github.com/shane-staret/claude-code-new-functionality-check/blob/main/skills/claude-code-new-functionality-check/resources/example-report.md). It is a real sweep: the summary, five full proposals and the ledger rows it wrote.
- **What one sweep looks like end to end:** [worked-example.md](https://github.com/shane-staret/claude-code-new-functionality-check/blob/main/skills/claude-code-new-functionality-check/resources/worked-example.md).

## How it works

```
weekly notice (hook) ──► /claude-code-new-functionality-check
  fetch     the helper downloads every official source into a local cache
  diff      only what is newer than the ledger's watermarks
  launches  every brand-new launch not yet judged (digest features, release-note entries,
            new docs pages), listed by the helper, not by a model
  inventory a generated snapshot of YOUR config (hooks, agents, skills, settings keys,
            MCP servers, plugins and marketplaces, by name only)
  evaluate  evaluator agents (local read only, no web) judge each change against the inventory,
            and one more judges every launch through the new-capability lens: what it makes
            possible for the system, where it would land, how broad the effect is, and the
            smallest first step. Every launch gets a disposition, so none is dropped silently
  verify    the helper re-finds every quoted sentence in the fetched text
  research  one researcher agent (web only, no local files) works a scrubbed agenda;
            its findings stay "leads" until the helper verifies them on an official page
  capture   proposals get ids in the ledger; everything else becomes a one-line note
  present   a fixed-shape summary; you decide by id
```

The skill is written so that it can be trusted with your configuration:
- **Nothing is applied.** A proposal's status changes only when you say so, and an accepted proposal is implemented later as its own task, under your normal review.
- **Every claim has a source.** Each proposal carries a verbatim quote from the official text, and a script (not the model) checks the quote is really there.
- **Privilege separation.** The agent that reads your config cannot reach the web. The agent that reads the web cannot read a single local file, so a malicious page has nothing to steal.
- **Nothing private leaves the machine.** Before any web search, the agenda is checked against your own denylist of private terms. Research is blocked until that list exists.
- **It fails closed.** A source that fails or changes format is reported as failed, never as "nothing new".

## Requirements

- Claude Code (built and tested on 2.1.295), with its Agent tool (subagents).
- bash 3.2 or later, curl and python3. jq is needed only to register the hook automatically.
- macOS is tested. The scripts are plain bash and are meant to work on Linux, but only macOS was tested.

## Install

```bash
git clone https://github.com/shane-staret/claude-code-new-functionality-check.git
bash claude-code-new-functionality-check/skills/claude-code-new-functionality-check/install.sh
bash claude-code-new-functionality-check/skills/claude-code-new-functionality-check/install.sh --yes --register-reminder --opt-in
```

The first run is a dry run: it lists what it would copy and changes nothing. The second run does the following:
- copies the skill, its two agents, the weekly reminder hook and the test suites into `~/.claude` (or `$CLAUDE_CONFIG_DIR`, which also needs the few settings in wiring.md's "Tunables");
- adds the reminder to `~/.claude/settings.json`;
- creates the ledger folder `~/.claude/claude-code-new-functionality-check/` with a denylist template.

It never deletes anything. A file it replaces is backed up first, under `~/.claude/backups/claude-code-new-functionality-check-install/`. Each flag is optional: leave out `--register-reminder` to run sweeps only by hand, and `--opt-in` on machines that should never sweep.

Then:
1. **Check that Claude Code sees the two agents.** Run `/agents`. If they are not listed yet, start a new session; recent versions pick up new agent files on their own.
2. **Add your private terms to `~/.claude/claude-code-new-functionality-check/denylist.txt`**, one per line: client and employer names, project code names, private repository names, people. Web research stays blocked until you do.
3. Optionally, beside the ledger:
   - `house-constraints.md`: rules of your own config that a proposal must respect;
   - `tracked-issues.md`: upstream issues you work around;
   - `backup.conf`: an off-disk backup folder for the ledger.

   [wiring.md](https://github.com/shane-staret/claude-code-new-functionality-check/blob/main/skills/claude-code-new-functionality-check/resources/wiring.md) describes each one.

**Install with Claude instead.** Open Claude Code in the cloned folder and say:

> Install the new-functionality check from this repository. Read README.md and skills/claude-code-new-functionality-check/resources/wiring.md, run install.sh as a dry run and show me the plan, then install it with my OK.

Every manual step is in [wiring.md](https://github.com/shane-staret/claude-code-new-functionality-check/blob/main/skills/claude-code-new-functionality-check/resources/wiring.md): the files, the settings entry, the opt-in, the denylist, an optional `CLAUDE.md` rule, tunables and uninstalling.

## First run: choose how far back to look

On the next prompt the hook prints a **never-run** notice, and Claude asks before starting anything.
- **Full backfill**, `/claude-code-new-functionality-check backfill`, reads every weekly digest and the whole changelog. On the author's machine that took 13 subagents and about 2.3 million subagent tokens.
- **Short backfill**, `/claude-code-new-functionality-check backfill since 2026-w33`, covers only what shipped after that week. It costs a fraction of a full backfill and is the sensible start. A week slug is the ISO year and week. The digest index at <https://code.claude.com/docs/en/whats-new> shows the weeks, and the helper lists them after it has fetched once (`fetch`, then `digests`, both subcommands of `claude_code_new_functionality_check.sh`).

**Catch up on launches that came out before you installed.** A first sweep judges launches from the last 60 days. To have older ones judged too, run `/claude-code-new-functionality-check new-capabilities since <YYYY-MM-DD>`. It runs the new-capability lens alone, one evaluator per window of at most 50 launches, and needs no backfill.

After that, the hook reminds you weekly. An incremental sweep costs a few hundred thousand tokens, and less when upstream has published nothing new (the weekly research lane still runs). It runs inside your interactive Claude Code session, using subagents; it never starts a separate headless Claude process. On a Claude subscription those tokens count against your plan's usage limits; with API-key billing they are charged at your model's token prices.

## Using it

| Say or type | What happens |
|---|---|
| `/claude-code-new-functionality-check` | an incremental sweep (what the weekly notice asks for) |
| `/claude-code-new-functionality-check backfill` or `backfill since <week>` | the first pass on a machine (it asks first) |
| `/claude-code-new-functionality-check new-capabilities since <YYYY-MM-DD>` | the new-capability lens alone, on launches since that date |
| `/claude-code-new-functionality-check status` | no network: when the last sweep ran, what it covered, how many proposals are open |
| `/claude-code-new-functionality-check present` | shows the open proposals again |
| `accept RW-0007 RW-0012` · `decline RW-0009: <why>` · `defer RW-0011 until <when>` | records your decision in the ledger |
| `walk me through hooks` | goes through the open proposals for one target, one at a time |
| `implement RW-0007` | starts building an accepted proposal, as its own task. When it is done, say `RW-0007 applied: <what changed and how it was checked>` and the skill records it |

Proposals that come from the new-capability lens are marked **[NEW]** in the ledger and get their own block in the summary, ranked by **breadth**: `system` (how the whole setup works), `several` (two or more parts) or `one` (a single part). To give the lens targets, you can describe what your Claude Code setup is for and where it hurts in `house-constraints.md` (wiring.md has a sample).

Proposals marked **sensitive** (a new hook command, a loosened permission, a plugin install, anything that runs unattended) are accepted only after a walk-through, never by bare id. Ids carry the `RW-` prefix because the skill was renamed from release-watch, and ids are never renamed.

## Files

```
skills/claude-code-new-functionality-check/
  SKILL.md                                  the procedure Claude follows
  claude_code_new_functionality_check.sh    the deterministic helper (fetch, diff, launches, verify, ledger)
  install.sh                                the installer
  resources/                                rubric, source registry, ledger format, research agenda,
                                            wiring, testing, worked example, example report, references
agents/claude-code-new-functionality-check-evaluator.md     tools: Read, Grep, Glob
agents/claude-code-new-functionality-check-researcher.md    tools: WebSearch, WebFetch
hooks/claude-code-new-functionality-check-reminder.sh       the weekly notice (UserPromptSubmit)
hooks/tests/test-claude-code-new-functionality-check-*.sh   four offline suites
```

At run time, the ledger lives in `~/.claude/claude-code-new-functionality-check/` and the cache in `~/.claude/tmp/claude-code-new-functionality-check/`.

## Tests

The four suites are offline and run against throwaway folders. They work from the clone and from `~/.claude/hooks/tests/` after installing:

```bash
bash claude-code-new-functionality-check/hooks/tests/test-claude-code-new-functionality-check-package.sh
bash claude-code-new-functionality-check/hooks/tests/test-claude-code-new-functionality-check-install.sh
bash claude-code-new-functionality-check/hooks/tests/test-claude-code-new-functionality-check-reminder.sh
bash claude-code-new-functionality-check/hooks/tests/test-claude-code-new-functionality-check-helper.sh
```

## Updating and uninstalling

- **Update:** run `git pull` in the clone, then rerun `bash claude-code-new-functionality-check/skills/claude-code-new-functionality-check/install.sh --yes`. Changed files are backed up before they are replaced. Your ledger and per-machine files live outside the skill folder, so an update never touches them.
- **Uninstall:** remove the hook's entry from `settings.json`, then move the skill folder, the two agents, the hook and its four test suites out of `~/.claude`. The ledger folder holds your decisions, so keep it if you may come back. [wiring.md](https://github.com/shane-staret/claude-code-new-functionality-check/blob/main/skills/claude-code-new-functionality-check/resources/wiring.md#uninstalling) has the details.

## License

MIT; see [LICENSE](https://github.com/shane-staret/claude-code-new-functionality-check/blob/main/LICENSE).
