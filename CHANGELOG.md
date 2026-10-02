# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
