/// What installing a package would do, found without installing it.
public enum PackageResolution: Sendable, Equatable {
    /// The newest version installs.
    case current(version: String)
    /// The newest version does not support this runtime, so an older one installs.
    case older(newest: String, installs: String)
    /// No version supports this runtime.
    case incompatible(newest: String)
    case notFound
    /// The lookup failed, for example without a network connection.
    case unavailable

    public var installVersion: String? {
        switch self {
        case let .current(version): version
        case let .older(_, installs): installs
        case .incompatible, .notFound, .unavailable: nil
        }
    }
}
