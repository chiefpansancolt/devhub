# DevHub

DevHub is a macOS menu bar app that shows outdated Homebrew packages, Node global packages (per Node version) and Ruby gems (per Ruby version). From the menu bar popover or a full window you can update everything, update a selection, update one package, or uninstall one. Every action is written to a timestamped history file you can read in the app. It supports several languages and light and dark mode.

Minimum macOS is 15 (Sequoia). Builds are universal (Apple Silicon and Intel).

## Status

Planning and design are finished. The build is starting.

The plan, the design mockups and the app icon live in the private repository [devhub-plan](https://github.com/chiefpansancolt/devhub-plan). Start with `docs/build-plan.md` there. It describes the architecture, the scanner commands, the history log format and the nine build phases.

## Languages

Strings live in two String Catalogs: `DevHub/Localizable.xcstrings` for the app and `Packages/DevHubCore/Sources/DevHubCore/Resources/Localizable.xcstrings` for messages from the core. English is the source language. German is translated.

After you add or change a string in the code, run `make build`, then update the catalogs from what the compiler found:

```
args() { for f in $(find build -path "$1" -name "*.stringsdata" | grep -v Extracted); do printf -- '--stringsdata %s ' "$f"; done; }
xcrun xcstringstool sync DevHub/Localizable.xcstrings $(args "*DevHub.build/Debug/DevHub.build/Objects-normal/arm64*")
xcrun xcstringstool sync Packages/DevHubCore/Sources/DevHubCore/Resources/Localizable.xcstrings $(args "*DevHubCore.build*Objects-normal/arm64*")
```

Then open the catalogs in Xcode to translate the new strings. To add a language, add it in the catalog editor, and add its name to the language picker in `AppearanceSettingsView.swift`. To try a language without changing the Mac, run the app with `-AppleLanguages "(de)"`.
