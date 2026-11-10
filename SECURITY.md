# Security Policy

## Reporting a vulnerability

Please **don't** open a public issue. Report it privately through GitHub instead:
**[Security → Report a vulnerability](https://github.com/Felix-Bergmann-Code/tokens/security/advisories/new)**.

You'll get a reply as soon as possible. Once a fix ships, you'll be credited unless you'd rather not be.

## What Tokens touches

Tokens is read-only and works entirely offline. It makes no network requests.

- **Reads** Claude Code logs in `~/.claude/projects` (or `$CLAUDE_CONFIG_DIR`) and Codex logs in `~/.codex/sessions` and `~/.codex/archived_sessions` (or `$CODEX_HOME`). From each line it keeps only token counts, model, timestamp and client type, never prompt or response text.
- **Reads** `~/.claude.json` for two fields only: the rate-limit tier and the subscription start date, used to detect your plan.
- **Writes** a usage cache to `~/Library/Application Support/Tokens/` and its own preferences. Delete that folder at any time to reset.
