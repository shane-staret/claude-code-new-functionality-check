# Tracked upstream issues (template)

Upstream Claude Code issues a config carries a **workaround** for. Every sweep runs `claude_code_new_functionality_check.sh issue-status <n>` and `issue-evidence <n>` for each row, so a workaround can be proposed for retirement the week upstream fixes it, and never earlier.

**This file is the empty template the skill ships.** Your own rows belong in `~/.claude/claude-code-new-functionality-check/tracked-issues.md` (the ledger folder). The helper reads that copy when it exists, so an update to the skill never overwrites your list. Copy this file there and add rows.

Rows are explicit on purpose. A config often mentions ticket and PR numbers from other repositories, and a heuristic scan for `#12345` would ask the wrong repository about them.

**To track a new issue:** add a row. `keywords` are comma-separated, case-insensitive substrings that a changelog bullet about the fix would contain (setting names, file names, error text). The helper parses this table, so keep it a plain pipe table with the issue number in the first column. For example:

`| <issue number> | someSetting, some-error-text | hooks/my-workaround.sh |` (the helper reads only rows whose first cell is a number, so this example line is ignored)

| issue | keywords | local workaround |
|---|---|---|
