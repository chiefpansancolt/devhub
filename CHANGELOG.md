# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Features

- A banner offers a newer Node or Ruby version that is not installed, when nvm, fnm, Volta or asdf (Node) or rbenv, rvm or asdf (Ruby) owns your versions. A newer patch of an installed line counts. Each banner has an Install button and an Install and set as default button, which run the manager's own commands
- A Node or Ruby version can be uninstalled through its manager (nvm, fnm, asdf, rbenv or rvm) with a trash button in the version's header or a right-click menu in the sidebar. DevHub always asks first, warns when it is the only version, and shows the reason when the manager refuses
- DevHub downloads the public release lists from nodejs.org and ruby-lang.org once a day for this. A "Check for new versions" switch in the Node and Ruby tabs of Settings turns it off
- Rust support: rustup toolchains and rustup itself, plus the tools installed with `cargo install`, each checked against the newest version on crates.io
- A Rust tab in Settings to choose the rustup program and to leave Cargo tools out
- Rust icons for the sidebar and Settings, with a white version for dark mode
- Node global packages from pnpm, Bun and Yarn 1, each as its own row next to the Node versions in the sidebar
- A section in the Node tab of Settings to choose the pnpm, Bun and Yarn programs and to turn a manager off
- Python support: tools installed with pipx and uv, grouped by manager, each checked for a newer version
- A Python tab in Settings to choose the pipx and uv programs and to turn a manager off
- A uv tool installed with an exact version or an upper bound shows no update, because `uv tool upgrade` cannot install a version outside that requirement
- Standard packages: a list for every tool (Homebrew, Node, Ruby, Rust and Python) in a window under the DevHub menu, next to Settings. Validate checks that each package exists and which version would install, and Install missing installs what a Node version, a Ruby version, a package manager or this Mac does not have yet
- A banner offers the standard packages when a new Node or Ruby version appears, with an optional notification. Nothing installs until you choose Install. Node installs the newest version that the Node version can run
- Export and Import of the standard lists in the File menu. The file holds only the lists, as JSON. An import asks whether to merge the names or replace the lists, shows what changes for each tool and installs nothing
- A package that Validate could not check shows why under "Could not check" (for example the first line npm printed), with more of the output on hover and in the output log
- Install is a new action: the progress strip, the output log, the popover and History know about it, and History has an Installs filter

### Changed

- History written by this version can hold `install` entries. An older version of DevHub skips those lines
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
