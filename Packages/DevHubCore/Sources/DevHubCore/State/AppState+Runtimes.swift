import Foundation

extension AppState {
    private static let releaseCacheLifetime: TimeInterval = 24 * 60 * 60

    public func dismissRuntimeOffer(_ offer: RuntimeOffer) {
        versionLedger?.dismiss(offer.id)
        updateRuntimeOffers()
    }

    public func installRuntime(_ offer: RuntimeOffer, asDefault: Bool) async {
        guard !isBusy else { return }
        await install([Self.installSubject(for: offer, asDefault: asDefault)])
    }

    public func startInstallRuntime(_ offer: RuntimeOffer, asDefault: Bool) {
        guard !isBusy else { return }
        updateTask = Task { await installRuntime(offer, asDefault: asDefault) }
    }

    static func installSubject(for offer: RuntimeOffer, asDefault: Bool) -> InstalledPackage {
        InstalledPackage(
            bucket: offer.bucket,
            kind: asDefault ? .runtimeAsDefault : .runtime,
            name: offer.bucket.rawValue,
            group: offer.manager.rawValue,
            installedVersion: "",
            availableUpdate: offer.version
        )
    }

    func startRuntimeReleaseCheck(force: Bool) {
        runtimeReleaseTask?.cancel()
        runtimeReleaseTask = Task { await checkRuntimeReleases(force: force) }
    }

    /// Asks the official release lists for the newest versions. A list that was fetched in the last day is not fetched again unless `force` is set.
    func checkRuntimeReleases(force: Bool) async {
        guard let runtimeReleaseSource else { return }
        for bucket in [Bucket.node, .ruby] where isRuntimeCheckEnabled(for: bucket) {
            if !force, let fetched = runtimeReleasesFetchedAt[bucket], now().timeIntervalSince(fetched) < Self.releaseCacheLifetime { continue }
            do {
                runtimeReleases[bucket] = try await runtimeReleaseSource.releases(for: bucket)
                runtimeReleasesFetchedAt[bucket] = now()
            } catch is CancellationError {
                return
            } catch {
                handle(.log(LogEntry(kind: .error, text: String(localized: "Could not check for new \(bucket.displayName) versions: \(error.localizedDescription)", bundle: .module))))
            }
        }
        updateRuntimeOffers()
    }

    func isRuntimeCheckEnabled(for bucket: Bucket) -> Bool {
        settings?.disabledRuntimeChecks.contains(bucket.rawValue) != true
    }

    func updateRuntimeOffers() {
        let dismissed = versionLedger?.snapshot.dismissed ?? []
        runtimeOffers = [Bucket.node, .ruby].filter(isRuntimeCheckEnabled).flatMap { bucket in
            RuntimeUpdatePlanner.offers(bucket: bucket, installed: runtimeVersions, releases: runtimeReleases[bucket] ?? [], dismissed: dismissed)
        }
    }
}

public struct RuntimeUninstallFailure: Equatable, Sendable {
    public let runtime: RuntimeVersion
    public let reason: String
}

extension AppState {
    /// The installed version that a scope shows, when its group is a version that a manager can uninstall.
    public func uninstallableRuntime(in scope: PackageScope) -> RuntimeVersion? {
        guard let group = scope.group else { return nil }
        return runtimeVersions.first { $0.bucket == scope.bucket && $0.version == group && $0.manager.canUninstallVersions }
    }

    public func installedRuntimeCount(of bucket: Bucket) -> Int {
        runtimeVersions.filter { $0.bucket == bucket }.count
    }

    public func uninstallRuntime(_ runtime: RuntimeVersion) async {
        guard !isBusy else { return }
        let subject = Self.uninstallSubject(for: runtime)
        runtimeUninstallFailure = nil
        uninstallProgress = UninstallProgress(packageID: subject.id, status: .updating)
        runningSince = Date()

        let outcome = await actions.uninstall(subject) { [weak self] event in
            await self?.handle(event)
        }
        runningSince = nil
        record([outcome], trigger: .manual)
        uninstallProgress = nil

        if case let .failed(reason) = outcome.status {
            runtimeUninstallFailure = RuntimeUninstallFailure(runtime: runtime, reason: reason)
            return
        }
        await refreshAfterAction()
    }

    public func startUninstallRuntime(_ runtime: RuntimeVersion) {
        Task { await uninstallRuntime(runtime) }
    }

    public func dismissRuntimeUninstallFailure() {
        runtimeUninstallFailure = nil
    }

    static func uninstallSubject(for runtime: RuntimeVersion) -> InstalledPackage {
        InstalledPackage(bucket: runtime.bucket, kind: .runtime, name: runtime.bucket.rawValue, group: runtime.manager.rawValue, installedVersion: runtime.version)
    }
}
