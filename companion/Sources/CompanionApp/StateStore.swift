import AppKit
import Combine
import Foundation
import UserNotifications
import CompanionCore

@MainActor
final class StateStore: ObservableObject {
    @Published private(set) var menuState: MenuState
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var activityReport: ActivityReport = ActivityReport.empty(scope: .today, generatedAt: 0)
    @Published private(set) var weeklyActivityReport: ActivityReport = ActivityReport.empty(scope: .week, generatedAt: 0)
    @Published private(set) var monthlyActivityReport: ActivityReport = ActivityReport.empty(scope: .month, generatedAt: 0)

    private(set) var configURL: URL
    private var config: CompanionConfig
    private var previous: [String: WorkbranchListDocument] = [:]
    private var lastRefreshResults: [RootResult] = []
    private var notificationTracker = NotificationTracker()
    private let readStateURL: URL
    private let activityRecorder: ActivityRecorder
    private var statusReadMarkers: StatusReadMarkers
    private var pendingBaselineStatusReadRoots: Set<String>
    private var missingRootConfirmations: [String: Int] = [:]
    private var debounceScheduler = DebounceScheduler(delay: 2.0)
    private var refreshCoordinator = RefreshCoordinator()
    private var debounceTimer: Timer?
    private var heartbeatTimer: Timer?
    private var rootWatcher: RootWatcher?
    private let loginItem: LoginItemControlling
    var configuredRoots: [String] { config.roots }
    var fontSettings: CompanionFontSettings { config.font }
    var colorTheme: CompanionColorTheme { config.colorTheme }

    init(configURL: URL = StateStore.defaultConfigURL(), loginItem: LoginItemControlling = SMAppServiceLoginItemController(), activityRecorder: ActivityRecorder = ActivityRecorder()) {
        self.configURL = configURL
        self.config = (try? CompanionConfig.load(from: configURL)) ?? (try! CompanionConfig(roots: []))
        self.loginItem = loginItem
        self.launchAtLogin = (loginItem.status == .enabled)
        self.readStateURL = Self.defaultReadStateURL(configURL: configURL)
        self.activityRecorder = activityRecorder
        if let markers = try? StatusReadMarkers.load(from: readStateURL) {
            self.statusReadMarkers = markers
            self.pendingBaselineStatusReadRoots = Self.pendingBaselineRoots(configuredRoots: config.roots, markers: markers)
        } else {
            self.statusReadMarkers = StatusReadMarkers()
            self.pendingBaselineStatusReadRoots = Set(config.roots)
        }
        var tracker = NotificationTracker()
        let initialGeneratedAt = Int(Date().timeIntervalSince1970)
        let initialEvents = activityRecorder.readEvents()
        let initialActivityReport = ActivityReport.make(events: initialEvents, scope: .today, generatedAt: initialGeneratedAt)
        self.activityReport = initialActivityReport
        self.weeklyActivityReport = ActivityReport.make(events: initialEvents, scope: .week, generatedAt: initialGeneratedAt)
        self.monthlyActivityReport = ActivityReport.make(events: initialEvents, scope: .month, generatedAt: initialGeneratedAt)
        self.menuState = MenuState.make(
            configuredRoots: config.roots,
            results: [],
            previous: nil,
            tracker: &tracker,
            isBaseline: true,
            statusReadMarkers: statusReadMarkers,
            activeSecondsByTask: initialActivityReport.activeSecondsByTask()
        )
        self.notificationTracker = tracker
        configureWatchers()
        refreshAll(isBaseline: true)
        startHeartbeat()
    }

    static func defaultConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("workbranch-companion")
            .appendingPathComponent("projects.md")
    }

    static func defaultReadStateURL(configURL: URL = StateStore.defaultConfigURL()) -> URL {
        configURL.deletingLastPathComponent().appendingPathComponent("read-state.json")
    }

    private static func pendingBaselineRoots(configuredRoots: [String], markers: StatusReadMarkers) -> Set<String> {
        Set(configuredRoots.filter { configuredRoot in
            !markers.roots.keys.contains { markerRoot in
                ProjectRootIdentity.matches(configuredRoot: configuredRoot, documentRoot: markerRoot)
            }
        })
    }

    func reloadConfig() {
        do {
            config = try CompanionConfig.load(from: configURL)
            statusMessage = "Config loaded"
        } catch {
            statusMessage = "Config error: \(error)"
            config = (try? CompanionConfig(roots: [])) ?? config
        }
        configureWatchers()
        refreshAll(isBaseline: true)
    }

    func refreshAll(isBaseline: Bool = false) {
        let roots = config.roots
        guard !roots.isEmpty else {
            refreshActivityReport()
            menuState = MenuState.make(configuredRoots: roots, results: [], previous: previous, tracker: &notificationTracker, isBaseline: true, statusReadMarkers: statusReadMarkers, activeSecondsByTask: activityReport.activeSecondsByTask())
            return
        }
        let refreshConfig = config
        Task { [weak self, refreshConfig] in
            let results = await Self.refreshGlobalAsync(config: refreshConfig)
            await MainActor.run {
                self?.apply(results: results, isBaseline: isBaseline)
            }
        }
    }

    func refresh(root: String, isBaseline: Bool = false) {
        refreshAll(isBaseline: isBaseline)
    }

    func noteFilesystemChange(root: String) {
        debounceScheduler.record(root: root, at: Date().timeIntervalSinceReferenceDate)
        scheduleDebounceDrain()
    }

    private func scheduleDebounceDrain() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 2.05, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.drainDebouncedRoots() }
        }
    }

    private func drainDebouncedRoots() {
        let roots = debounceScheduler.dueRoots(at: Date().timeIntervalSinceReferenceDate)
        for root in roots { refreshFromWatcher(root: root) }
    }

    private func refreshFromWatcher(root: String) {
        guard refreshCoordinator.begin(root: root) else { return }
        let refreshConfig = config
        Task { [weak self, root, refreshConfig] in
            let results = await Self.refreshGlobalAsync(config: refreshConfig)
            await MainActor.run {
                guard let self else { return }
                self.apply(results: results, isBaseline: false)
                if self.refreshCoordinator.finish(root: root) == .runAgain {
                    self.noteFilesystemChange(root: root)
                }
            }
        }
    }

    func apply(results: [RootResult], isBaseline: Bool) {
        lastRefreshResults = results
        let previousSnapshot = previous
        var successfulDocuments: [WorkbranchListDocument] = []
        for result in results {
            switch result {
            case .success(let document):
                successfulDocuments.append(document)
                clearMissingRootConfirmations(afterSuccessfulRefreshOf: document.root)
            case .failure(let root, _):
                recordMissingRootIfNeeded(root: root)
            }
        }
        let events = ActivityEvent.diff(
            previous: previousSnapshot,
            next: successfulDocuments,
            observedAt: Int(Date().timeIntervalSince1970),
            isBaseline: isBaseline
        )
        do {
            try activityRecorder.append(events)
        } catch {
            statusMessage = "Activity log failed: \(error)"
        }
        for document in successfulDocuments {
            previous[document.root] = document
        }
        refreshActivityReport()
        if baselinePendingStatusReadMarkers(with: successfulDocuments) {
            persistStatusReadMarkers()
        }
        menuState = MenuState.make(
            configuredRoots: config.roots,
            results: results,
            previous: previous,
            tracker: &notificationTracker,
            isBaseline: isBaseline,
            statusReadMarkers: statusReadMarkers,
            activeSecondsByTask: activityReport.activeSecondsByTask()
        )
        for notification in menuState.notificationsToSend {
            sendNotification(title: "Workbranch notification", body: "\(notification.task): \(notification.count) unread")
        }
    }

    private func clearMissingRootConfirmations(afterSuccessfulRefreshOf documentRoot: String) {
        missingRootConfirmations.removeValue(forKey: documentRoot)
        for root in config.roots where ProjectRootIdentity.matches(configuredRoot: root, documentRoot: documentRoot) {
            missingRootConfirmations.removeValue(forKey: root)
        }
    }

    @discardableResult
    private func baselinePendingStatusReadMarkers(with documents: [WorkbranchListDocument]) -> Bool {
        var didChange = false
        for document in documents where isPendingBaselineStatusReadRoot(document.root) {
            statusReadMarkers.markBaselineRead(documents: [document])
            pendingBaselineStatusReadRoots.remove(document.root)
            for root in config.roots where ProjectRootIdentity.matches(configuredRoot: root, documentRoot: document.root) {
                pendingBaselineStatusReadRoots.remove(root)
            }
            didChange = true
        }
        return didChange
    }

    private func isPendingBaselineStatusReadRoot(_ documentRoot: String) -> Bool {
        pendingBaselineStatusReadRoots.contains(documentRoot) ||
            pendingBaselineStatusReadRoots.contains { configuredRoot in
                ProjectRootIdentity.matches(configuredRoot: configuredRoot, documentRoot: documentRoot)
            }
    }

    private func recordMissingRootIfNeeded(root: String) {
        switch ProjectRootSelfHeal.classify(root: root) {
        case .available, .unavailable:
            missingRootConfirmations.removeValue(forKey: root)
        case .trueDeletionCandidate:
            let count = (missingRootConfirmations[root] ?? 0) + 1
            missingRootConfirmations[root] = count
            guard count >= 2 else { return }
            forgetDeletedRoot(root)
        }
    }

    private func forgetDeletedRoot(_ root: String) {
        do {
            let newConfig = try config.removingRoot(root)
            try newConfig.write(to: configURL)
            self.config = newConfig
            previous.removeValue(forKey: root)
            missingRootConfirmations.removeValue(forKey: root)
            statusMessage = "Removed deleted project root: \(root)"
            sendNotification(title: "Workbranch root removed", body: "Deleted project root was removed from companion config: \(root)")
            configureWatchers()
        } catch {
            statusMessage = "Root self-heal failed: \(error)"
        }
    }

    func saveMemo(root: String, task: String, text: String) {
        runWorkbranchAction(root: root) { builder in builder.editMemo(root: root, task: task, text: text) }
        refresh(root: root)
    }

    func perform(_ action: MenuAction) {
        switch action {
        case .editMemo:
            break
        case .markStatusRead(let root, let task, let updatedAt):
            markStatusRead(root: root, task: task, updatedAt: updatedAt)
        case .clearNotifications(let root, let task):
            runWorkbranchAction(root: root) { $0.clearNotifications(root: root, task: task) }
            refresh(root: root)
        case .openTerminal(let root, let task):
            runWorkbranchAction(root: root) { $0.openTerminal(root: root, task: task) }
        case .openIDE(let root, let task):
            runWorkbranchAction(root: root) { $0.openIDE(root: root, task: task) }
        case .revealFinder(let root, let task):
            runWorkbranchAction(root: root) { $0.revealFinder(root: root, task: task) }
        case .copyPath(let path):
            runExternal(ActionBuilder(workbranchBin: "workbranch").copyPath(path))
        case .openConfig:
            openConfig()
        case .refresh:
            refreshAll()
        case .quit:
            quit()
        }
    }

    func markStatusRead(root: String, task: String, updatedAt: Int) {
        statusReadMarkers.markRead(root: root, task: task, updatedAt: updatedAt)
        persistStatusReadMarkers()
        rebuildMenuStateFromPrevious()
    }

    private func refreshActivityReport() {
        let generatedAt = Int(Date().timeIntervalSince1970)
        let events = activityRecorder.readEvents()
        activityReport = ActivityReport.make(events: events, scope: .today, generatedAt: generatedAt)
        weeklyActivityReport = ActivityReport.make(events: events, scope: .week, generatedAt: generatedAt)
        monthlyActivityReport = ActivityReport.make(events: events, scope: .month, generatedAt: generatedAt)
    }

    private func persistStatusReadMarkers() {
        do {
            try statusReadMarkers.write(to: readStateURL)
        } catch {
            statusMessage = "Read state failed: \(error)"
        }
    }

    private func rebuildMenuStateFromPrevious() {
        menuState = MenuState.make(
            configuredRoots: config.roots,
            results: lastRefreshResults,
            previous: previous,
            tracker: &notificationTracker,
            isBaseline: true,
            statusReadMarkers: statusReadMarkers,
            activeSecondsByTask: activityReport.activeSecondsByTask()
        )
    }

    func openConfig() {
        do {
            _ = try CompanionConfig.ensureGUIConfig(at: configURL)
            configureWatchers()
            NSWorkspace.shared.open(configURL)
        } catch {
            statusMessage = "Open config failed: \(error)"
        }
    }

    @discardableResult
    func saveAppearance(fontName: String, fontSize: Double, colorTheme: CompanionColorTheme) -> Bool {
        do {
            let normalizedFontName = fontName.trimmingCharacters(in: .whitespacesAndNewlines)
            let nextConfig = try CompanionConfig(
                roots: config.roots,
                workbranchBin: config.workbranchBin,
                font: CompanionFontSettings(name: normalizedFontName, size: fontSize),
                colorTheme: colorTheme
            )
            try nextConfig.write(to: configURL)
            config = nextConfig
            statusMessage = "Settings saved"
            return true
        } catch {
            statusMessage = "Settings error: \(error)"
            return false
        }
    }

    func saveColorTheme(_ colorTheme: CompanionColorTheme) {
        saveAppearance(
            fontName: config.font.name,
            fontSize: config.font.size,
            colorTheme: colorTheme
        )
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let errorDescription: String?
        do {
            try loginItem.setEnabled(enabled)
            errorDescription = nil
        } catch {
            errorDescription = String(describing: error)
        }
        let outcome = LoginItemToggleOutcome.resolve(
            requested: enabled,
            statusAfter: loginItem.status,
            errorDescription: errorDescription
        )
        launchAtLogin = outcome.launchAtLogin
        statusMessage = outcome.message
    }

    func quit() {
        rootWatcher?.stop()
        heartbeatTimer?.invalidate()
        NSApplication.shared.terminate(nil)
    }

    private func runWorkbranchAction(root: String, build: (ActionBuilder) -> ExternalCommand) {
        do {
            let client = try CLIClient(config: config)
            runExternal(build(ActionBuilder(workbranchBin: client.workbranchBin)))
        } catch {
            statusMessage = "Action failed: \(error)"
        }
    }

    private func runExternal(_ command: ExternalCommand) {
        if let standardInput = command.standardInput {
            runStandardInputExternal(command, standardInput: standardInput)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: command.cwd ?? FileManager.default.currentDirectoryPath)
        process.environment = Self.augmentedEnvironment()
        do {
            try process.run()
            if command.detached {
                statusMessage = "Action started"
            } else {
                process.waitUntilExit()
                statusMessage = process.terminationStatus == 0 ? "Action complete" : "Action failed"
            }
        } catch {
            statusMessage = "Action failed: \(error)"
        }
    }

    private func runStandardInputExternal(_ command: ExternalCommand, standardInput: String) {
        let environment = Self.augmentedEnvironment()
        Task { [weak self, command, standardInput, environment] in
            let message = await Task.detached(priority: .utility) {
                Self.runStandardInputProcess(command: command, standardInput: standardInput, environment: environment)
            }.value
            await MainActor.run {
                self?.statusMessage = message
            }
        }
    }

    private nonisolated static func runStandardInputProcess(command: ExternalCommand, standardInput: String, environment: [String: String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: command.cwd ?? FileManager.default.currentDirectoryPath)
        process.environment = environment
        let input = Pipe()
        process.standardInput = input
        do {
            try process.run()
            if let data = standardInput.data(using: .utf8) { input.fileHandleForWriting.write(data) }
            try? input.fileHandleForWriting.close()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? "Action complete" : "Action failed"
        } catch {
            return "Action failed: \(error)"
        }
    }

    private nonisolated static func augmentedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let additions = ["/opt/homebrew/bin", "/usr/local/bin", NSString(string: "~/.local/bin").expandingTildeInPath]
        env["PATH"] = (additions + [env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        return env
    }

    private func sendNotification(title: String, body: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func configureWatchers() {
        rootWatcher?.stop()
        let configDirectory = configURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        } catch {
            statusMessage = "Config watcher failed: \(error)"
        }
        rootWatcher = RootWatcher(roots: config.roots, configURL: configURL, onRootChange: { [weak self] root in
            self?.noteFilesystemChange(root: root)
        }, onConfigChange: { [weak self] in
            self?.reloadConfig()
        })
        rootWatcher?.start()
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
    }

    private nonisolated static func refreshGlobalAsync(config: CompanionConfig) async -> [RootResult] {
        await Task.detached(priority: .utility) {
            refreshGlobal(config: config)
        }.value
    }

    private nonisolated static func refreshGlobal(config: CompanionConfig) -> [RootResult] {
        do {
            let client = try CLIClient(config: config)
            let document = try client.listGlobalJSON()
            let successes = document.projects.map { RootResult.success($0) }
            let failures = document.errors.map { RootResult.failure(root: $0.root, message: $0.message) }
            return successes + failures
        } catch {
            return config.roots.map { .failure(root: $0, message: String(describing: error)) }
        }
    }
}
