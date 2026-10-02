import DevHubCore
import SwiftUI

struct RustSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var check: PathCheck?

    var body: some View {
        @Bindable var settings = settings
        let installation = Toolchain.detect(settings: settings.values).rust
        let effectivePath = settings.values.rustPath ?? installation?.rustup.path

        Form {
            Section {
                PathRow(
                    title: "rustup program",
                    chosenPath: $settings.values.rustPath,
                    detectedText: installation?.rustup.path ?? String(localized: "Not found in the usual places"),
                    check: check,
                    kind: .file
                )
                if let cargo = installation?.cargo {
                    LabeledContent("Cargo") { Text(cargo.path).font(.system(size: 12, design: .monospaced)).textSelection(.enabled) }
                }
            } header: {
                Label {
                    Text("Location")
                } icon: {
                    BucketBadge(bucket: .rust, size: 14)
                }
            }

            Section("Update checks") {
                Toggle("Include Cargo tools", isOn: $settings.values.rustIncludeCargoTools)
                .clickable()
                    .disabled(installation?.cargo == nil)
                Text("Cargo asks crates.io for the newest version of each tool.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task(id: effectivePath) {
            check = nil
            if let effectivePath {
                check = await PathValidation.rustup(path: effectivePath, runner: CommandRunner())
            } else {
                check = .problem(String(localized: "Rust was not found. Choose the rustup program."))
            }
        }
    }
}
