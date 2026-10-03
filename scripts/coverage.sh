#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

package=Packages/DevHubCore
ignore='(\.build|Tests)/'

swift test --package-path "$package" --build-system swiftbuild --enable-code-coverage

report=$(swift test --package-path "$package" --build-system swiftbuild --show-codecov-path)
profile="$(dirname "$report")/default.profdata"
binary="$(dirname "$(dirname "$report")")/DevHubCoreTests.xctest/Contents/MacOS/DevHubCoreTests"

for file in "$profile" "$binary"; do
    [ -f "$file" ] || { echo "coverage.sh: missing $file" >&2; exit 1; }
done

# Codecov matches files by their path in the repository, so the lcov paths are made relative.
xcrun llvm-cov export -format=lcov -instr-profile="$profile" -ignore-filename-regex="$ignore" "$binary" \
    | sed "s#^SF:$PWD/#SF:#" > coverage.lcov

xcrun llvm-cov report -instr-profile="$profile" -ignore-filename-regex="$ignore" "$binary" | tail -n 1
echo "Wrote coverage.lcov"
