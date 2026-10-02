import DevHubCore
import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Appearance") {
                HStack(spacing: 14) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        ThemeCard(theme: theme, isSelected: settings.values.theme == theme) {
                            settings.values.theme = theme
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            Section("Language") {
                Picker("Language", selection: $settings.values.language) {
                    Text("Same as system").tag(String?.none)
                    Text(verbatim: "English").tag(String?.some("en"))
                    Text(verbatim: "Deutsch").tag(String?.some("de"))
                    Text(verbatim: "日本語").tag(String?.some("ja"))
                    Text(verbatim: "简体中文").tag(String?.some("zh-Hans"))
                }
                .clickable()
                if settings.values.language != AppEffects.launchLanguage {
                    HStack {
                        Text("Restart DevHub to change the language.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart DevHub") { AppEffects.restart() }
                            .clickable()
                    }
                }
            }

            Section("Menu bar icon") {
                Picker("Icon style", selection: $settings.values.menuBarIconStyle) {
                    Text("Icon").tag(MenuBarIconStyle.iconOnly)
                    Text("Icon and count").tag(MenuBarIconStyle.iconAndCount)
                    Text("Count").tag(MenuBarIconStyle.countOnly)
                }
                .clickable()
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 8) {
                preview
                    .frame(width: 130, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: isSelected ? 2.5 : 1))
                Text(title).font(.system(size: 12, weight: isSelected ? .bold : .regular))
            }
        }
        .buttonStyle(.plain)
        .clickable()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var title: LocalizedStringKey {
        switch theme {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch theme {
        case .system:
            ZStack {
                window(dark: false)
                window(dark: true).mask(DiagonalHalf())
            }
        case .light: window(dark: false)
        case .dark: window(dark: true)
        }
    }

    private func window(dark: Bool) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(dark ? Color(white: 0.14) : Color(white: 0.89)).frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(dark ? Color(white: 0.3) : Color(white: 0.82)).frame(width: 60, height: 6)
                RoundedRectangle(cornerRadius: 3).fill(dark ? Color(white: 0.3) : Color(white: 0.82)).frame(width: 76, height: 6)
                RoundedRectangle(cornerRadius: 3).fill(Color.accentColor).frame(width: 40, height: 6)
            }
            .padding(10)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(dark ? Color(white: 0.17) : .white)
    }
}

private struct DiagonalHalf: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.maxX, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: 0, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
