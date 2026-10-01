# DevHub

DevHub is a macOS menu bar app that shows outdated Homebrew packages, Node global packages (per Node version) and Ruby gems (per Ruby version). From the menu bar popover or a full window you can update everything, update a selection, update one package, or uninstall one. Every action is written to a timestamped history file you can read in the app. It supports several languages and light and dark mode.

Minimum macOS is 15 (Sequoia). Builds are universal (Apple Silicon and Intel).

## Status

Planning and design are finished. The build is starting.

The plan, the design mockups and the app icon live in the private repository [devhub-plan](https://github.com/chiefpansancolt/devhub-plan). Start with `docs/build-plan.md` there. It describes the architecture, the scanner commands, the history log format and the nine build phases.
