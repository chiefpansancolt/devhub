import DevHubCore
import SwiftUI

extension Bucket {
    var logo: String {
        switch self {
        case .homebrew: "BucketHomebrew"
        case .node: "BucketNode"
        case .ruby: "BucketRuby"
        }
    }
}

struct BucketBadge: View {
    let bucket: Bucket
    var size: CGFloat = 28

    var body: some View {
        Image(bucket.logo)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct CountPill: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}
