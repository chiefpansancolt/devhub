import DevHubCore
import SwiftUI

struct RuntimeUpdateBanners: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if !state.isBusy, !state.runtimeOffers.isEmpty {
            VStack(spacing: 8) {
                ForEach(state.runtimeOffers) { offer in
                    RuntimeUpdateBanner(offer: offer)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }
}

private struct RuntimeUpdateBanner: View {
    @Environment(AppState.self) private var state
    let offer: RuntimeOffer

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                summary
                Spacer(minLength: 8)
                actions
            }
            VStack(alignment: .leading, spacing: 8) {
                summary
                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    actions
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private var summary: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.circle")
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(offer.bucket.displayName) \(offer.version) is available")
                    .font(.system(size: 13, weight: .semibold))
                details
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Install") { state.startInstallRuntime(offer, asDefault: false) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .clickable()
            Button("Install and set as default") { state.startInstallRuntime(offer, asDefault: true) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .clickable()
            Button("Dismiss") { state.dismissRuntimeOffer(offer) }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .clickable()
        }
        .fixedSize()
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("You have \(offer.installedVersion) with \(offer.manager.rawValue).")
            if offer.bucket == .ruby {
                Text("Ruby builds from source, so this takes several minutes.")
            }
        }
    }
}
