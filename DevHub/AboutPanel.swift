import AppKit

@MainActor
enum AboutPanel {
    private static let website = URL(string: "https://devhub.chiefpansancolt.dev")!
    private static let repository = URL(string: "https://github.com/chiefpansancolt/devhub")!
    private static let issues = URL(string: "https://github.com/chiefpansancolt/devhub/issues/new/choose")!
    private static let license = URL(string: "https://github.com/chiefpansancolt/devhub/blob/main/LICENSE")!

    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits()])
        AppActivation.bringToFront()
    }

    private static func credits() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 8
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]

        func text(_ string: String, link: URL? = nil) -> NSAttributedString {
            var attributes = attributes
            attributes[.link] = link
            return NSAttributedString(string: string, attributes: attributes)
        }

        let links: [(String, URL)] = [
            (String(localized: "Website"), website),
            (String(localized: "Source code"), repository),
            (String(localized: "Report an issue"), issues)
        ]
        let result = NSMutableAttributedString()
        result.append(text(String(localized: "Keeps Homebrew, Node and Ruby up to date from the menu bar.") + "\n"))
        for (index, (title, url)) in links.enumerated() {
            if index > 0 { result.append(text("  ·  ")) }
            result.append(text(title, link: url))
        }
        result.append(text("\n"))
        result.append(text(String(localized: "Released under the MIT License."), link: license))
        return result
    }
}
