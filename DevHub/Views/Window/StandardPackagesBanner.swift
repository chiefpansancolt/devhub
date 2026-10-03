import DevHubCore
import SwiftUI

struct StandardPackagesBanners: View {
    @Environment(AppState.self) private var state
    let scope: PackageScope

    var body: some View {
        let offers = state.standardOffers(in: scope)
        if !state.isBusy, !offers.isEmpty {
            VStack(spacing: 8) {
                ForEach(offers) { offer in
                    StandardPackagesBanner(offer: offer)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }
}

private struct StandardPackagesBanner: View {
    @Environment(AppState.self) private var state
    let offer: StandardOffer

    private static let shownNames = 6

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title.font(.system(size: 13, weight: .semibold))
                Text("Missing from this version: \(names)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("Install") { state.startInstallStandard(bucket: offer.bucket, group: offer.version) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .clickable()
            Button("Dismiss") { state.dismissStandardOffer(offer) }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .clickable()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private var label: String {
        "\(offer.bucket.displayName) \(offer.version)"
    }

    private var title: Text {
        offer.bucket == .ruby ? Text("Install standard gems into \(label)") : Text("Install standard packages into \(label)")
    }

    private var names: String {
        let shown = offer.missing.prefix(Self.shownNames).map(\.name).joined(separator: ", ")
        let more = offer.missing.count - Self.shownNames
        return more > 0 ? "\(shown) +\(more)" : shown
    }
}
