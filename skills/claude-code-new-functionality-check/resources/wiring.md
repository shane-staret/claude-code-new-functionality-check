# Wiring the new-functionality check on a machine

`install.sh`, in this skill's folder, does everything on this page; the package `README.md` shows how to run it. This page is the manual version: what goes where, and why. It is for a person or an AI wiring the package by hand, or repairing it after something overwrote the config. The suites in `testing-claude-code-new-functionality-check.md` prove the package works, and `--status` (near the end of this page) tells you whether this machine is wired.

Paths are written as `~/.claude`. For a different config folder, see "Tunables".

## The files

| From the package | To | Job |
|---|---|---|
| `skills/claude-code-new-functionality-check/` (the whole folder) | `~/.claude/skills/claude-code-new-functionality-check/` | the procedure (`/claude-code-new-functionality-check`), its helper `claude_code_new_functionality_check.sh`, the resources and the installer |
| `agents/claude-code-new-functionality-check-evaluator.md` | `~/.claude/agents/` | judges fetched upstream text against your config. Tools `Read, Grep, Glob` only: no web, no edits |
| `agents/claude-code-new-functionality-check-researcher.md` | `~/.claude/agents/` | researches the open web. Tools `WebSearch, WebFetch` only: it cannot read a local file |
| `hooks/claude-code-new-functionality-check-reminder.sh` | `~/.claude/hooks/` | the weekly notice, and the single owner of the sweep state (`--status`, `--write-state`) |
| `hooks/tests/test-claude-code-new-functionality-check-*.sh` | `~/.claude/hooks/tests/` (optional) | the four offline suites |

The helper, the hook and the installer must be executable. Requirements: bash 3.2 or later, curl and python3; jq only for registering the hook. A running session picks up new skills and settings. Recent versions pick up new agent files too: run `/agents`, and if the two agents are not listed, start a new Claude Code session.

## The settings entry (the weekly notice)

Add one command hook to `~/.claude/settings.json`, in a `UserPromptSubmit` group with no `matcher` (a group that runs on every prompt):

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/claude-code-new-functionality-check-reminder.sh",
            "statusMessage": "Checking Claude Code release freshness..."
          }
        ]
      }
    ]
  }
}
```

If such a group already exists, append the inner object to its `hooks` list instead of adding a second group, and keep everything else in the file. Then run `jq -e . ~/.claude/settings.json`: a file that does not parse silently disables every setting in it.

The hook costs about 20 ms per prompt. It never blocks, never uses the network, and prints nothing on a machine that has not opted in. Without the entry the skill still works; you just have to remember to run it.

## Opting a machine in

Everything stays dormant until the ledger folder exists, so you can copy the files to every machine you use and let only one of them sweep:

```bash
mkdir -p ~/.claude/claude-code-new-functionality-check     # or: install.sh --yes --opt-in
```

The next prompt gets the **never-run** notice, which tells Claude to ask you before the first sweep. You choose between:
- a **full backfill** (`/claude-code-new-functionality-check backfill`): every weekly digest and the whole changelog. On the author's machine that took 13 subagents and about 2.3 million subagent tokens;
- a **short backfill** (`/claude-code-new-functionality-check backfill since <week slug>`): only the digests after that week and the changelog after it. The slugs (for example `2026-w33`) come from the helper's `digests` subcommand. A few weeks cost a fraction of the full pass.

After that, each weekly sweep is incremental: the new digest, a short changelog tail and one research lane. That is a few hundred thousand tokens, and almost nothing when upstream has published nothing new.

Use one sweeper per group of machines. The ledger is per-machine on purpose, so a copied config can never overwrite your decisions; two sweepers would also triage the same releases twice.

## The denylist (required before any web research)

`~/.claude/claude-code-new-functionality-check/denylist.txt` names what must never leave the machine in a search query: client and employer names, project code names, private repository names, people.
- Write one term per line. A line starting with `#` is a comment, and terms shorter than four characters are ignored.
- Matching ignores case and finds the term anywhere in a line.
- Your username, home folder and short hostname are always checked as well.

`scrub-check` refuses every research agenda while the file is missing or lists no term, because a check against nothing proves nothing. Until you seed it, the research half of a sweep cannot run. `install.sh --opt-in` writes a commented template; add your terms before the first sweep.

## Optional per-machine files

These live beside the ledger, never in the skill folder, so updating the skill never overwrites them.

| File | Contents | Read by |
|---|---|---|
| `house-constraints.md` | your config's own rules that a proposal must not break ("no hook starts a headless session", "deny rules stay as they are"), and facts that change a judgment (how large your CLAUDE.md is, how many machines share the config) | the evaluator, every run; never the researcher |
| `tracked-issues.md` | upstream issues your config works around, in the table shape of `resources/tracked-issues.md` | the helper (`tracked-issues`, `issue-status`, `issue-evidence`) |
| `backup.conf` | one line, `BACKUP_DIR=<a folder that leaves the machine>` | the helper's `backup`, at the end of each sweep |

Without `house-constraints.md`, the evaluator uses the general constraints in `resources/applicability-rubric.md`. A small one looks like this:

```markdown
# House constraints (read by the evaluator; never sent to the web)

| Constraint | Why |
|---|---|
| No hook, agent or skill starts a headless Claude session | headless runs bill separately and run unattended |
| `permissions.deny` rules are only ever added, never loosened | they guard secrets and force pushes |
| Hooks must stay fast: under 50 ms per prompt | they run on every prompt on every machine |

Facts: CLAUDE.md is about 40 KB; three machines share this config; one of them is the sweeper.
```

## An optional CLAUDE.md rule

The notices explain themselves, so this is optional. To make the habit explicit, add this to `~/.claude/CLAUDE.md`:

```markdown
## Claude Code currency
- On a `NEW-FUNCTIONALITY-CHECK:` notice: finish my current request first, then run `/claude-code-new-functionality-check` at a natural pause in the same session, or tell me you are deferring it. The never-run notice means ask me before any backfill.
- A sweep never applies anything. A proposal's status (`RW-NNNN`) changes only when I say so.
- Before building or reworking a hook, skill, agent or settings mechanism, check the proposal index in `~/.claude/claude-code-new-functionality-check/ledger.md` and the current docs for a built-in feature that already does it.
```

## Tunables

Set these in `settings.json` under `env`, and only when a default is wrong for you.

| Variable | Default | Effect |
|---|---|---|
| `CLAUDE_NEW_FUNCTIONALITY_CHECK` | on | `0` silences the notices; `--status` and `--write-state` still work |
| `CLAUDE_NEW_FUNCTIONALITY_CHECK_INTERVAL_DAYS` | `7` | how old the last sweep may be before the notice fires |
| `CLAUDE_NEW_FUNCTIONALITY_CHECK_RENOTICE_SECS` | `86400` | the minimum gap between notices, so a deferred sweep does not nag on every prompt |
| `CLAUDE_NEW_FUNCTIONALITY_CHECK_QUIET_DIRS` | none | colon-separated folders where a due notice stays silent until the sweep is twice overdue (a client-work tree, say) |
| `CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR` | `~/.claude/claude-code-new-functionality-check` | the ledger folder |

**A config folder other than `~/.claude` (`CLAUDE_CONFIG_DIR`).** `install.sh` copies into it, but the scripts' defaults and the skill's commands say `~/.claude`. To use it anyway:
- set `CLAUDE_NEW_FUNCTIONALITY_CHECK_DIR`, `NEW_FUNCTIONALITY_CHECK_CLAUDE_DIR` (the config the inventory describes), `NEW_FUNCTIONALITY_CHECK_CACHE_DIR` and `NEW_FUNCTIONALITY_CHECK_STATE_FILE` to paths in your folder;
- write the hook command with your folder's path;
- tell Claude where the skill's helper lives.

## Where things live at run time

| Path | Holds | Safe to clear? |
|---|---|---|
| `~/.claude/claude-code-new-functionality-check/` | the ledger: proposals and your decisions, coverage watermarks, the run log, `snapshots/` (watched-page baselines) and `archive/` (same-disk copies taken before each write) | no: it is the record of your decisions |
| `~/.claude/tmp/claude-code-new-functionality-check/cache/` | fetched pages, slices, the generated inventory, saved agent replies, the `verify-lead` page cache | yes; the next `fetch` refills it |
| `~/.claude/tmp/claude-code-new-functionality-check-state.json` | when the last sweep finished and what it covered | yes; the machine then counts as due (never-run is decided by the ledger, not by this file) |

The `verify-lead` cache (`cache/leads/`) keeps one file per distinct URL, at most 5 MB each, and nothing prunes it. A year of weekly sweeps comes to tens of megabytes.

## Backing up the ledger

`snapshot` keeps same-disk copies under `archive/`. That protects against a bad edit, not against a lost disk.

`claude_code_new_functionality_check.sh backup [<dir>]` writes one dated `claude_code_new_functionality_check_ledger_<UTC>.tar.gz` into `<dir>`, or into the `BACKUP_DIR` named in `backup.conf`.
- The tarball holds the ledger files and `snapshots/`. It leaves out `archive/`, and never includes the fetch cache.
- It never overwrites or deletes an earlier tarball.
- The sweep's last step runs it whenever `backup.conf` exists.

Two things to know before choosing the folder: the tarball contains `denylist.txt` (your private terms) and every proposal's text, and old tarballs pile up (a few hundred KB each) until you prune them.

## Checking the wiring

```bash
bash ~/.claude/hooks/claude-code-new-functionality-check-reminder.sh --status
```

It prints one of:
- `DORMANT`: no ledger folder, so this machine has not opted in;
- `NEVER-RUN`: opted in, no sweep yet;
- `DUE` or `FRESH`, with what the last sweep covered.

It also names the installed CLI version and the state file it read.

## When something else manages your config

A tool that regenerates `settings.json` or replaces `~/.claude/agents/` (a dotfiles sync, a team deploy) undoes this wiring without a sound: the hook file survives unregistered, and the notices simply stop. After such a deploy, rerun `install.sh --yes --register-reminder`; it skips whatever is already in place. Better still, add the files and the settings entry to whatever does the deploying.

## Uninstalling

1. Remove the hook's entry from `settings.json`, or restore the copy that `install.sh --register-reminder` saved under `~/.claude/backups/claude-code-new-functionality-check-install/<UTC>.<random>/`. Then run `jq -e . ~/.claude/settings.json`.
2. Move the skill folder, the two agent files, the hook and its suites out of `~/.claude`.
3. The ledger folder holds your decisions: keep it, or move it somewhere else. Without it the hook stays dormant, even if its entry remains.
