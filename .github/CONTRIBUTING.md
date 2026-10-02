# Contributing to DevHub

First and foremost, thank you for taking the time to contribute to DevHub. Any
help is appreciated to make DevHub better and stronger.

## Code of Conduct

This project and everyone participating in it is governed by the
[DevHub Code of Conduct](https://github.com/chiefpansancolt/devhub/blob/main/.github/CODE_OF_CONDUCT.md).
By participating, you are expected to uphold this code. Please report
unacceptable behavior to github@chiefpansancolt.dev.

## How can I contribute

### Reporting bugs

Before creating a bug report, please check
[the open bugs](https://github.com/chiefpansancolt/devhub/issues?q=is%3Aopen+is%3Aissue+label%3Abug),
because the problem may already be reported. When you create a report, include
as many details as possible. Fill out the
[bug report form](https://github.com/chiefpansancolt/devhub/issues/new?assignees=chiefpansancolt&labels=bug%2Cnew&template=bug_report.yml&title=%5BBug%5D%3A+).
The information it asks for helps resolve issues faster. The History page in
DevHub keeps the command, the exit code and the output of every action, so a
copy of the failing entry is the most useful thing you can attach.

> Note: If you find a closed issue that looks like the same problem, open a new
> issue and link to the original one in the body.

### Suggesting enhancements

Before creating an enhancement suggestion, please check
[the open suggestions](https://github.com/chiefpansancolt/devhub/issues?q=is%3Aopen+is%3Aissue+label%3Aenhancement).
Then fill in the
[feature request form](https://github.com/chiefpansancolt/devhub/issues/new?assignees=chiefpansancolt&labels=enhancement%2Cnew&template=feature_request.yml&title=%5BEnhancement%5D%3A+)
and describe the steps you would take if the feature existed.

### Translations

DevHub is translated into German, Spanish, French, Brazilian Portuguese,
Russian, Japanese, Korean and Simplified Chinese. The translations have not had
a native review yet, so corrections are very welcome. Use the
[translation form](https://github.com/chiefpansancolt/devhub/issues/new?labels=translation%2Cnew&template=translation.yml&title=%5BTranslation%5D%3A+)
or open a pull request that edits the String Catalogs.

### Code contributions

Look for issues tagged
[help wanted](https://github.com/chiefpansancolt/devhub/issues?q=is%3Aopen+is%3Aissue+label%3A%22help+wanted%22).

## Development setup

You need macOS 15 or newer, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/chiefpansancolt/devhub.git
cd devhub
make test    # run the DevHubCore tests
make run     # build and open the app
```

Run `make help` to see every target. The README has an overview of the project
layout.

### Conventions

- Every user-visible string goes through a String Catalog. Run `make check-strings`
  to confirm that every string is translated into every language.
- Every control a person can click shows the pointing hand. Use the `.clickable()`
  modifier, and place it before `.disabled(...)`.
- Use `chevron.forward` and `chevron.backward` so layouts mirror in right-to-left
  languages.
- Tests use recorded command output as fixtures. A test must never run a real
  `brew`, `npm` or `gem` command.
- Write a comment only when the code departs from a standard pattern, such as a
  workaround or a platform quirk. Prefer a clear name or type over a comment.

## Commit messages

DevHub uses [Conventional Commits](https://www.conventionalcommits.org/). Start
the subject with a type, then a colon and a short summary in the imperative
mood, with no period at the end. Keep the subject under about 72 characters.

| Type        | Use it for                                              |
| ----------- | ------------------------------------------------------- |
| `feat:`     | A new feature that people can see or use                |
| `fix:`      | A bug fix                                               |
| `chore:`    | Maintenance, dependencies, tooling and configuration    |
| `docs:`     | Documentation only                                      |
| `test:`     | Adding or changing tests only                           |
| `refactor:` | A code change that fixes no bug and adds no feature     |
| `ci:`       | Changes to the GitHub Actions workflows                 |

Add a scope in parentheses when it helps, such as `fix(history): ...` or
`feat(node): ...`. Use the body to explain why the change is needed, in plain
sentences. Put one kind of change in each commit, so that the type is accurate
and the changelog can be written from the history.

```
fix: rename a local that shadowed the outdated(in:) method

announceNewUpdates named a local variable outdated and then called the
outdated(in:) method inside its own initializer. The compiler on the CI
runner rejects that, so the DevHubCore tests failed to build.
```

Pull request titles follow the same format.

## Pull requests

The process described here has several goals:

- Maintain DevHub's quality
- Fix problems that are important to users
- Engage the community in working toward the best possible DevHub
- Enable a sustainable system for DevHub's maintainers to review contributions

Please follow these steps to have your contribution considered:

- Follow all instructions in
  [the template](https://github.com/chiefpansancolt/devhub/blob/main/.github/PULL_REQUEST_TEMPLATE.md)
- After you submit your pull request, verify that all status checks are passing

<details>
<summary>What if the status checks are failing?</summary>

If a status check is failing and you believe the failure is unrelated to your
change, please leave a comment on the pull request explaining why. A maintainer
will re-run the status check. If we conclude that the failure was a false
positive, we will open an issue to track the problem.

</details>

While the steps above must be satisfied before a pull request is reviewed, the
reviewers may ask for additional design work, tests, or other changes before the
pull request can be accepted.
