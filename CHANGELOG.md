# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-10-03

### Features

- Rust support: rustup toolchains and rustup itself, plus the tools installed with `cargo install`, checked against crates.io, with a Rust tab in Settings
- Python support: tools installed with pipx and uv, grouped by manager, with a Python tab in Settings
- Node global packages from pnpm, Bun and Yarn 1, shown next to the Node versions
- Standard packages: one list per tool (Homebrew, Node, Ruby, Rust and Python) in its own window. Validate checks that each package exists, and Install missing installs what a version, a package manager or this Mac does not have yet. A banner offers the list when a new Node or Ruby version appears. Nothing installs until you choose Install
- Export and Import of the standard lists in the File menu, as JSON, with Merge or Replace
- Sync of the standard lists through a private GitHub repository. Connect an account in the new Accounts tab in Settings, and DevHub keeps the lists of your Macs the same. A sync never installs anything. GitHub's `repo` permission is needed to create a private repository, and the tab explains it before you connect
- New Node and Ruby versions: a banner offers a newer version, with Install and Install and set as default, when nvm, fnm, Volta, asdf, rbenv or rvm owns your versions. DevHub looks at nodejs.org and ruby-lang.org once a day, and a switch in Settings turns it off
- Uninstall a Node or Ruby version through its manager (nvm, fnm, asdf, rbenv or rvm), from the version's header or its sidebar menu, after a confirmation

### Changed

- History can hold `install` entries, which older versions of DevHub skip
- History moves to `⌘6`, because Rust takes `⌘4` and Python takes `⌘5`

## [1.0.0] - 2026-10-01

First release.

### Features

- Menu bar popover that lists outdated Homebrew packages, Node global packages (per Node version) and Ruby gems (per Ruby version), with Update all and a per-package Update button
- Full window with a sidebar that filters by tool, Node or Ruby version, and formula or cask, an Updates list and an All installed list, a details pane, an output log and a progress strip with Cancel
- Update all, update the selection, update one package, or uninstall one package
- Node updates install the highest version that each Node version supports instead of `@latest`
- History of every check, update and uninstall in `~/Library/Logs/DevHub/history.jsonl`, with a History page, filters, export and retention settings
- Settings for checks, notifications, appearance, the menu bar icon, custom tool paths, version selection and history
- Notifications for new updates, scheduled checks, checks on wake, and an option to open at login
- Application menus with keyboard shortcuts
- An About panel with the version, the license and links to the website, the source code and the issue tracker, also reachable from the popover menu
- Light and dark mode, VoiceOver labels and keyboard navigation in the lists
- Translations for German, Spanish, French, Brazilian Portuguese, Russian, Japanese, Korean and Simplified Chinese, with a language picker

### Chores

- Universal (Apple Silicon and Intel) DMG from `make release`, signed ad hoc and not notarized
- GitHub Actions for CI and releases, issue and pull request templates, and Dependabot for Actions
