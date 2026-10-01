import DevHubCore
import SwiftUI

struct HomebrewSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var check: PathCheck?

    var body: some View {
        @Bindable var settings = settings
        let installation = Toolchain.detect(settings: settings.values).homebrew
        let effectivePath = settings.values.brewPath ?? installation?.executable.path

        Form {
            Section {
                PathRow(
                    title: "brew program",
                    chosenPath: $settings.values.brewPath,
                    detectedText: installation?.executable.path ?? String(localized: "Not found in the usual places"),
                    check: check,
                    kind: .file
                )
                if let installation {
                    LabeledContent("Prefix") { Text(installation.prefix.path).font(.system(size: 12, design: .monospaced)).textSelection(.enabled) }
                    LabeledContent("Cellar") { Text(installation.prefix.appending(path: "Cellar").path).font(.system(size: 12, design: .monospaced)).textSelection(.enabled) }
                    LabeledContent("Caskroom") { Text(installation.prefix.appending(path: "Caskroom").path).font(.system(size: 12, design: .monospaced)).textSelection(.enabled) }
                }
            } header: {
                Label {
                    Text("Location")
                } icon: {
                    BucketBadge(bucket: .homebrew, size: 14)
                }
            }

            Section("Update checks") {
                Toggle("Run brew update before each check", isOn: $settings.values.brewRefreshIndex)
                .clickable()
                Toggle("Include casks", isOn: $settings.values.brewIncludeCasks)
                .clickable()
                Toggle("Include casks that update themselves", isOn: $settings.values.brewIncludeSelfUpdatingCasks)
                .clickable()
                    .disabled(!settings.values.brewIncludeCasks)
            }

            Section("Update options") {
                Toggle("Remove old versions after updating", isOn: $settings.values.brewCleanupAfterUpdate)
                .clickable()
            }
        }
        .formStyle(.grouped)
        .task(id: effectivePath) {
            check = nil
            if let effectivePath {
                check = await PathValidation.homebrew(path: effectivePath, runner: CommandRunner())
            } else {
                check = .problem(String(localized: "Homebrew was not found. Choose the brew program."))
            }
        }
    }
}
