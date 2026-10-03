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
