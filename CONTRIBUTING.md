# Contributing to Tokens

Thanks for wanting to help! Pull requests are very welcome: bug fixes, price updates, support for more agents, docs, anything.

## Getting started

1. Fork the repo and clone your fork.
2. Build and run:
   ```bash
   ./scripts/build.sh --install
   ```
   You need macOS 26+ and Xcode 26+. There are no dependencies; it's a plain Swift package.
3. Create a branch: `git checkout -b my-change`.
4. Make your change, check it still builds with `swift build`, and try it in the running app.
5. Open a pull request against `main`. Describe what changed and, for anything visual, add a screenshot (`Tokens --snapshot <dir>` renders every tab in light and dark mode).

Not sure where to start? Look for issues labelled **good first issue** or **help wanted**, or open an issue to talk an idea through before you build it.

## Common contributions

- **Price updates**: edit `Sources/Tokens/Pricing.swift`. Entries are matched by prefix, most specific first, so put a new `claude-foo-5-1` above `claude-foo`. Link the official pricing page in the PR.
- **New agents**: add a `Source`/`Provider` in `Models.swift`, discovery and parsing in `Scanner.swift`, and a watched folder in `Store.swift`. Parse incrementally from the stored byte offset, like the existing parsers.
- **Debugging numbers**: `.build/release/Tokens --dump --rebuild` ignores the cache and prints a daily summary.

## Guidelines

- **Local only.** Tokens never makes network requests and only reads what it needs from agent logs. PRs that add networking, analytics or upload anything won't be merged.
- **Keep it light.** Watch folders instead of polling, and parse only new bytes.
- **No third-party dependencies** unless there's a very good reason. Discuss it in an issue first.
- **Match the existing style**: SwiftUI, small focused files, comments that explain *why*.
- **One topic per PR.** Smaller PRs get reviewed and merged faster.
- **Don't commit your own logs or snapshots.** They can contain prompts, file paths and project names. Redact them before pasting into an issue.

## Reporting bugs

Open an issue using the bug template. Include your macOS version, which agents you use and steps to reproduce.

## Security

Please don't open public issues for security problems. See [SECURITY.md](SECURITY.md).

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
