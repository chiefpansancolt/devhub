.DEFAULT_GOAL := help
.PHONY: project build run test scan help

project:
	@xcodegen generate

build: project
	@xcodebuild -project DevHub.xcodeproj -scheme DevHub -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath build build

run: build
	@open build/Build/Products/Debug/DevHub.app

test:
	@swift test --package-path Packages/DevHubCore

help:
	@echo "make project   Generate DevHub.xcodeproj from project.yml (needs xcodegen)"
	@echo "make build     Build the app into ./build"
	@echo "make run       Build and open the app"
	@echo "make test      Run the DevHubCore tests"
	@echo "make scan      Scan this machine for outdated packages and print the result"

scan:
	@swift run -q --package-path Packages/DevHubCore devhub-scan --no-update
