#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

version=$(awk '/MARKETING_VERSION/ { print $2 }' project.yml)
name="DevHub-$version"
products=build/Build/Products/Release
staging=dist/staging

xcodegen generate
xcodebuild -quiet -project DevHub.xcodeproj -scheme DevHub -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath build build

rm -rf dist
mkdir -p "$staging"
cp -R "$products/DevHub.app" "$staging/"
ln -s /Applications "$staging/Applications"

codesign --verify --deep --strict "$staging/DevHub.app"
lipo -archs "$staging/DevHub.app/Contents/MacOS/DevHub"

hdiutil create -volname DevHub -srcfolder "$staging" -fs HFS+ -format UDZO -ov "dist/$name.dmg" >/dev/null
rm -rf "$staging"

(cd dist && shasum -a 256 "$name.dmg" | tee "$name.dmg.sha256")
