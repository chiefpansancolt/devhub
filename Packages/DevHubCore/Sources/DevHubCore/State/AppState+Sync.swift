import Foundation

extension AppState {
    private static let maxSyncAttempts = 3

    /// Connects the sync to the app. `lists` reads the live standard lists and `apply` writes merged lists back into the settings.
    public func configureSync(
        _ services: SyncServices,
        lists: @escaping @MainActor () -> StandardPackageLists,
        apply: @escaping @MainActor (StandardPackageLists) -> Void
    ) {
        syncConfiguration = SyncConfiguration(services: services, lists: lists, apply: apply)
        publishSyncState()
    }

    func publishSyncState() {
        let snapshot = syncConfiguration?.services.ledger.snapshot
        syncAccountLogin = snapshot?.login
        syncResult = snapshot?.lastResult
        syncLastSuccessAt = snapshot?.lastSuccessAt
    }

    // MARK: Signing in

    public func connectGitHub() {
        guard let services = syncConfiguration?.services, signInTask == nil else { return }
        signInTask = Task { [weak self] in
            await self?.signIn(using: services)
            self?.signInTask = nil
        }
    }

    public func cancelSignIn() {
        signInTask?.cancel()
    }

    public func dismissSignInFailure() {
        guard case .failed = signIn else { return }
        signIn = .idle
    }

    private func signIn(using services: SyncServices) async {
        signIn = .requesting
        let flow = GitHubDeviceFlow(clientID: services.clientID, transport: services.transport, sleep: services.sleep, now: now)
        do {
            let code = try await flow.start()
            signIn = .waiting(DeviceCodeInfo(userCode: code.userCode, verificationURL: code.verificationURL, expiresAt: code.expiresAt))
            let token = try await flow.awaitToken(for: code)
            try await services.tokenStore.save(token)
            let login: String
            do {
                login = try await GitHubRepoClient(transport: services.transport, token: token, sleep: services.sleep).login()
            } catch {
                try? await services.tokenStore.delete()
                throw error
            }
            services.ledger.connect(login: login)
            signIn = .idle
            publishSyncState()
            requestSync()
        } catch is CancellationError {
            signIn = .idle
        } catch {
            let failure = error as? SyncError
            signIn = .failed(failure?.errorDescription ?? error.localizedDescription)
            logSync(failure?.logDetail ?? error.localizedDescription)
        }
    }

    public func disconnectGitHub() async {
        guard let services = syncConfiguration?.services else { return }
        syncTask?.cancel()
        try? await services.tokenStore.delete()
        services.ledger.clear()
        publishSyncState()
    }

    // MARK: Syncing

    public func syncNow() {
        requestSync()
    }

    func requestAutomaticSync() {
        guard settings?.syncStandardPackagesAutomatically == true else { return }
        requestSync()
    }

    /// Starts a sync, or marks that another one must follow the one that is running.
    func requestSync() {
        guard syncConfiguration?.services.ledger.snapshot.login != nil else { return }
        if syncTask != nil {
            syncAgain = true
            return
        }
        isSyncing = true
        syncTask = Task { [weak self] in
            repeat {
                guard let self, !Task.isCancelled else { return }
                self.syncAgain = false
                await self.runSync()
            } while self?.syncAgain == true
            self?.syncTask = nil
            self?.isSyncing = false
        }
    }

    func syncAndWait() async {
        requestSync()
        await syncTask?.value
    }

    /// Uploads a few seconds after the last edit. A newer edit replaces the wait, and never stops a sync that has started.
    func scheduleSyncPush() {
        guard let configuration = syncConfiguration, !isApplyingSyncedLists,
              settings?.syncStandardPackagesAutomatically == true else { return }
        guard configuration.services.ledger.snapshot.login != nil else { return }
        pushTask?.cancel()
        let services = configuration.services
        pushTask = Task { [weak self] in
            do { try await services.sleep(services.pushDelay) } catch { return }
            self?.requestSync()
        }
    }

    private func runSync() async {
        guard let configuration = syncConfiguration else { return }
        let ledger = configuration.services.ledger
        do {
            let outcome = try await syncOnce(configuration)
            ledger.recordSuccess(base: outcome.base, summary: outcome.summary, at: now())
            syncedListEditRevision = outcome.editRevision
        } catch is CancellationError {
            return
        } catch {
            let failure = error as? SyncError
            if failure == .unauthorized { try? await configuration.services.tokenStore.delete() }
            let message = failure?.errorDescription ?? error.localizedDescription
            ledger.recordFailure(kind: failure?.kind ?? .other, message: message, at: now())
            logSync(failure?.logDetail ?? error.localizedDescription)
        }
        publishSyncState()
    }

    private struct SyncOutcome {
        let base: StandardPackageLists
        let summary: SyncSummary
        let editRevision: Int
    }

    private func syncOnce(_ configuration: SyncConfiguration) async throws -> SyncOutcome {
        let services = configuration.services
        guard let token = try await services.tokenStore.token(), let login = services.ledger.snapshot.login else { throw SyncError.unauthorized }
        let client = GitHubRepoClient(transport: services.transport, token: token, sleep: services.sleep)
        let repository = try await client.ensureRepository(login: login)
        var summary = SyncSummary(added: 0, removed: 0)

        for _ in 0..<Self.maxSyncAttempts {
            let remoteFile = try await client.readFile(login: login)
            try Task.checkCancellation()
            let (remote, unreadable) = try Self.readRemote(remoteFile)
            let local = configuration.lists()
            let editRevision = listEditRevision

            // Settings that were lost leave an empty list. Only an edit by the user may empty the remote list.
            var base = services.ledger.snapshot.base
            if local.isEmpty, !base.isEmpty, editRevision == syncedListEditRevision { base = StandardPackageLists() }
            let merged = StandardListsMerge.merge(base: base, local: local, remote: remote)

            if merged != local {
                isApplyingSyncedLists = true
                configuration.apply(merged)
                isApplyingSyncedLists = false
                let change = StandardListsMerge.summary(from: local, to: merged)
                summary = SyncSummary(added: summary.added + change.added, removed: summary.removed + change.removed)
            }
            if let unreadable { throw SyncError.remoteFileNotUsable(unreadable) }
            if merged == remote { return SyncOutcome(base: merged, summary: summary, editRevision: editRevision) }

            let data = try StandardListsFile.make(from: merged, tools: Set(Bucket.allCases), now: now()).encoded()
            do {
                _ = try await client.writeFile(data, login: login, sha: remoteFile?.sha, retryingNotFound: repository == .created)
            } catch SyncError.conflict {
                continue
            }
            return SyncOutcome(base: merged, summary: summary, editRevision: editRevision)
        }
        throw SyncError.tooManyConflicts
    }

    /// Reads the file in the repository. A file from a newer DevHub is read as far as possible and reported, so the sync never uploads over it.
    private static func readRemote(_ file: RemoteFile?) throws -> (StandardPackageLists, RemoteFileProblem?) {
        guard let file else { return (StandardPackageLists(), nil) }
        do {
            let decoded = try StandardListsFile.decode(file.data)
            return (decoded.file.lists, decoded.skippedEntries > 0 ? .hasUnreadableEntries(decoded.skippedEntries) : nil)
        } catch StandardListsFile.ReadError.newerVersion(let version) {
            throw SyncError.remoteFileNotUsable(.newerVersion(version))
        } catch StandardListsFile.ReadError.notAStandardPackagesFile {
            throw SyncError.remoteFileNotUsable(.notOurFile)
        } catch {
            throw SyncError.remoteFileNotUsable(.unreadable)
        }
    }

    private func logSync(_ detail: String) {
        handle(.log(LogEntry(kind: .error, text: String(localized: "GitHub sync: \(detail)", bundle: .module))))
    }
}
