# Source registry

What a sweep researches. **The registry, not the session's memory, decides breadth**: every sweep works every row. The user extends or prunes it.

Tier 1 rows are fetched by `claude_code_new_functionality_check.sh fetch`, and their URLs are constants at the top of that script (the package suite checks that the two agree — edit both). Tier 2 and 3 rows are worked by the `claude-code-new-functionality-check-researcher` agent from the agenda the skill hands it; adding a row there needs no code.

| tier | source | URL | fetched by | good for |
|---|---|---|---|---|
| 1 core | What's New index | https://code.claude.com/docs/en/whats-new.md | helper `fetch` | which weekly digests exist |
| 1 core | What's New weekly digests | https://code.claude.com/docs/en/whats-new | helper `fetch` (`/<year>-w<week>.md`) | curated notable features, with links to their reference docs; `launches` lists every feature for the new-capability lens |
| 1 core | Changelog (dated docs mirror) | https://code.claude.com/docs/en/changelog.md | helper `fetch` | every change, revert, and removal |
| 1 core | Changelog (GitHub raw, fallback) | https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md | helper `fetch` | fallback when the docs mirror fails or does not parse |
| 1 extended | npm `latest` (canary only — a tripped canary is a CORE `DEGRADED` row; a canary that cannot run is an extended `SKIPPED` row and still makes the run partial) | https://registry.npmjs.org/@anthropic-ai/claude-code/latest | helper `fetch` | proves the changelog is not stale or partly unparsed |
| 1 extended | Docs index | https://code.claude.com/docs/llms.txt | helper `fetch` + `watch-diff` | a NEW docs page is a new feature surface; `launches` lists each new page (keyed by its URL) for the new-capability lens, even while the digests lag |
| 1 extended | Best practices | https://code.claude.com/docs/en/best-practices.md | helper `fetch` + `watch-diff` | how Anthropic says to work |
| 1 extended | Official plugin marketplace | https://raw.githubusercontent.com/anthropics/claude-plugins-official/main/.claude-plugin/marketplace.json | helper `fetch` + `watch-diff` (plugin names) | new official plugins |
| 1 extended | Support release notes | https://support.claude.com/en/articles/12138966-release-notes | helper `fetch` (rendered to text) | models, entitlements, plan and billing policy; product launches across Claude (apps, Labs products, connectors, Claude Code surfaces), which `launches` lists for the new-capability lens |
| 1 extended | Tracked upstream issues | https://api.github.com/repos/anthropics/claude-code/issues | helper `issue-status` / `issue-evidence` | workaround retirement (`tracked-issues.md`) |
| 2 official long-form | Anthropic engineering blog | https://www.anthropic.com/engineering | researcher | harness, agent, and context engineering practice |
| 2 official long-form | Claude blog, Claude Code category | https://claude.com/blog | researcher | product practice and case studies |
| 2 official long-form | Anthropic news and Claude product announcements | https://www.anthropic.com/news | researcher | launches announced outside the release notes (they reach the new-capability lens after `verify-lead`) |
| 2 ecosystem | releases of the plugins you rely on, for example superpowers | https://github.com/obra/superpowers/releases | researcher | updates to installed plugins (add one row per plugin you depend on) |
| 3 open web | budgeted WebSearch | (none) | researcher | real-world usage, pitfalls, community patterns — **leads only** |

## Rules that go with the registry

- **Tiers decide trust.** `official-docs` > `official-blog` > `vendor` > `community` / `issue-tracker`. A community or vendor claim is a *lead* until `claude_code_new_functionality_check.sh verify-lead <official-url> <quote>` succeeds for it.
- **Core vs extended decides state.** The sweep is recorded (`--write-state`) once the CORE rows succeeded. A failed extended row is reported with its consecutive-failure count in the ledger's coverage table; three in a row means "fix or prune this source", never a daily paid re-sweep.
- **Deliberately not watched** (each can arrive later as its own proposal):
  - the GitHub releases Atom feed (it duplicates the changelog, which already carries dates);
  - line diffs of the large reference pages (noisy; the changelog covers them);
  - the developer platform (API) release notes. They serve the application layer, and this skill judges the Claude Code system. A platform launch that matters reaches a sweep through the research lane;
  - site sitemaps (no publish dates, and bulk re-stamps);
  - the news and product-announcement listings as fetched pages (no feed, and paging happens in the browser). The researcher's long-form lane reads them instead.
