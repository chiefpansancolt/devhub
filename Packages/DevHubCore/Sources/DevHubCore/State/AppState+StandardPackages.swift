import Foundation

extension AppState {
    private static let concurrentLookups = 6

    // MARK: Reading

    public func standardStatus(for bucket: Bucket) -> [StandardTargetStatus] {
        StandardStatus.status(
            for: bucket,
            lists: settings?.standardPackages ?? StandardPackageLists(),
            groups: knownVersions[bucket] ?? [],
            packages: results[bucket]?.packages ?? []
        )
    }

    /// The entries that a list would hold if it were filled from one target.
    public func standardFillEntries(bucket: Bucket, group: String?) -> [StandardEntry] {
        StandardStatus.entries(installedIn: StandardTarget(bucket: bucket, group: group), packages: results[bucket]?.packages ?? [])
    }

    public func isStandardOfferDismissed(bucket: Bucket, version: String) -> Bool {
        versionLedger?.snapshot.dismissed.contains(VersionLedger.key(bucket, version)) == true
    }

    // MARK: Validating

    /// Looks up every entry of the list for one target, without installing anything. The result is keyed by `StandardEntry.id`.
    public func validateStandard(bucket: Bucket, group: String?) async -> [String: PackageResolution] {
        let entries = (settings?.standardPackages ?? StandardPackageLists()).entries(for: bucket)
        let target = StandardTarget(bucket: bucket, group: group)
        guard let scanner = scanners[bucket] else {
            let notSetUp = PackageResolution.unavailable(reason: String(localized: "\(bucket.displayName) is not set up on this Mac.", bundle: .module), details: nil)
            return Dictionary(uniqueKeysWithValues: entries.map { ($0.id, notSetUp) })
        }
        let subjects = entries.map { StandardStatus.subject(for: $0, in: target) }
        let cannotCheck = PackageResolution.unavailable(reason: String(localized: "DevHub cannot check this package here.", bundle: .module), details: nil)
        let resolutions = await BoundedConcurrency.map(subjects, limit: Self.concurrentLookups) { subject in
            await scanner.resolveInstall(of: subject) ?? cannotCheck
        }
        logUnavailable(entries, resolutions)
        return Dictionary(uniqueKeysWithValues: zip(entries.map(\.id), resolutions))
    }

    /// The output log keeps what a lookup printed, so a package that could not be checked can be explained.
    private func logUnavailable(_ entries: [StandardEntry], _ resolutions: [PackageResolution]) {
        for (entry, resolution) in zip(entries, resolutions) {
            guard case let .unavailable(reason, details) = resolution else { continue }
            handle(.log(LogEntry(kind: .error, text: "\(entry.name): \(reason)")))
            for line in (details ?? "").split(separator: "\n") {
                handle(.log(LogEntry(kind: .error, text: "    \(line)")))
            }
        }
    }

    // MARK: Installing

    /// Installs the standard packages that a target is missing. A Node version installs the newest version that it can run.
    public func installStandard(bucket: Bucket, group: String?) async {
        guard !isBusy, let status = standardStatus(for: bucket).first(where: { $0.target.group == group }), !status.missing.isEmpty else { return }
        isPreparingInstall = true
        var subjects = status.missing.map { StandardStatus.subject(for: $0, in: status.target) }

        if status.target.bucket == .node, status.target.isVersion, let scanner = scanners[.node] {
            let resolutions = await BoundedConcurrency.map(subjects, limit: Self.concurrentLookups) { await scanner.resolveInstall(of: $0) }
            subjects = zip(subjects, resolutions).compactMap { subject, resolution in
                switch resolution {
                case .notFound?:
                    skip(subject, String(localized: "Skipped \(subject.name): no package with that name was found.", bundle: .module))
                    return nil
                case .incompatible?:
                    skip(subject, String(localized: "Skipped \(subject.name): no version of it supports Node \(status.target.group ?? "").", bundle: .module))
                    return nil
                case let resolution?:
                    return subject.withUpdate(resolution.installVersion, isPinned: false)
                case nil:
                    return subject
                }
            }
        }

        isPreparingInstall = false
        guard !Task.isCancelled, !subjects.isEmpty else { return }
        await install(subjects)
    }

    public func startInstallStandard(bucket: Bucket, group: String?) {
        guard !isBusy else { return }
        updateTask = Task { await installStandard(bucket: bucket, group: group) }
    }

    private func skip(_ package: InstalledPackage, _ message: String) {
        handle(.log(LogEntry(kind: .error, text: message)))
    }

    // MARK: Offers

    public func dismissStandardOffer(_ offer: StandardOffer) {
        versionLedger?.dismiss(offer.id)
        updateStandardOffers()
    }

    func updateStandardOffers() {
        guard let versionLedger, let settings else {
            standardOffers = []
            return
        }
        let versions: [Bucket: [String]] = [
            .node: (knownVersions[.node] ?? []).filter { $0.first?.isNumber == true },
            .ruby: knownVersions[.ruby] ?? []
        ]
        versionLedger.seedIfNeeded(with: Set(versions.flatMap { bucket, list in list.map { VersionLedger.key(bucket, $0) } }))

        var installed: [Bucket: [String: Set<String>]] = [:]
        for (bucket, list) in versions {
            guard let result = results[bucket], !(result.packages.isEmpty && result.issues.contains { $0.group == nil }) else { continue }
            let failed = Set(result.issues.compactMap(\.group))
            installed[bucket] = Dictionary(uniqueKeysWithValues: list.filter { !failed.contains($0) }.map { version in
                (version, Set(result.packages.filter { $0.group == version }.map(\.name)))
            })
        }
        standardOffers = StandardPackagePlanner.offers(
            versions: versions,
            installed: installed,
            lists: settings.standardPackages,
            ledger: versionLedger.snapshot,
            disabledBanners: Set(settings.disabledStandardBanners.compactMap(Bucket.init(rawValue:)))
        )
    }

    func announceStandardOffers() async {
        guard settings?.notifyStandardPackages == true, let notifier, let versionLedger else { return }
        let fresh = standardOffers.filter { !versionLedger.snapshot.notified.contains($0.id) }
        guard !fresh.isEmpty else { return }
        versionLedger.markNotified(Set(fresh.map(\.id)))
        let names = fresh.map { "\($0.bucket.displayName) \($0.version)" }.formatted(.list(type: .and, width: .narrow))
        await notifier.send(
            UpdateNotification(title: String(localized: "Standard packages are missing", bundle: .module), body: names),
            playSound: notificationOptions.playsSound
        )
    }
}
