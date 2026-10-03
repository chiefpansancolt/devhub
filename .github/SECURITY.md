# Security Policy

## Supported versions

Security fixes are made in the latest release only.

## Reporting a vulnerability

Please do not report security problems in a public issue.

Use GitHub's private reporting instead. Open the Security tab of this
repository and choose **Report a vulnerability**, or go straight to
[the advisory form](https://github.com/chiefpansancolt/devhub/security/advisories/new).
If you cannot use GitHub, write to github@chiefpansancolt.dev.

Include the DevHub version, your macOS version, and the steps to reproduce the
problem. You can expect a first response within a week.

## What DevHub does on your Mac

These facts help when you judge the impact of a report.

- DevHub runs `brew`, `npm` and `gem` as your user to list, update and uninstall
  packages. It never uses `sudo` and never asks for an administrator password.
- App Sandbox is off, because the app has to run those tools.
- DevHub makes two network requests itself, at most once a day: it downloads the public release lists from nodejs.org and ruby-lang.org to find new Node and Ruby versions. No data about your machine is sent, and a switch in Settings turns it off. The package managers it runs make their own requests.
- The action history is stored in `~/Library/Logs/DevHub/history.jsonl`, and the
  settings are stored in the app's preferences. Nothing is sent anywhere.
- Releases are signed ad hoc and are not notarized yet.
