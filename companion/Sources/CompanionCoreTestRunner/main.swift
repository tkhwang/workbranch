import Foundation
import CompanionCore

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure(message: message) }
}

func expectThrows(_ message: String, _ body: () throws -> Void) throws {
    do {
        try body()
        throw TestFailure(message: "Expected throw: \(message)")
    } catch is TestFailure {
        throw TestFailure(message: "Expected throw: \(message)")
    } catch {
        return
    }
}

func runModelsAndMenuStateTests() throws {
    let json = Data("""
    {
      "schemaVersion": 1,
      "project": "fullstack",
      "root": "/tmp/fullstack",
      "tasks": [
        {
          "name": "feat-draft",
          "path": "/tmp/fullstack/feat-draft",
          "memoTitle": "견적 \\"API\\" 경로",
          "notiCount": 2,
          "repos": [
            {"name": "backend", "branch": "feat/draft", "dirty": true},
            {"name": "frontend", "branch": "feat/draft", "dirty": false}
          ]
        },
        {
          "name": "docs_notes",
          "path": "/tmp/fullstack/docs_notes",
          "memoTitle": "",
          "notiCount": 0,
          "repos": []
        }
      ]
    }
    """.utf8)
    let document = try WorkbranchListDocument.decode(json)
    try expect(document.schemaVersion == 1, "schema version")
    try expect(document.project == "fullstack", "project")
    try expect(document.root == "/tmp/fullstack", "root")
    try expect(document.tasks.count == 2, "task count")
    try expect(document.tasks[0].memoTitle == "견적 \"API\" 경로", "memo round trip")
    try expect(document.tasks[0].notiCount == 2, "noti count")
    try expect(document.tasks[0].repos[0].dirty, "dirty repo")

    try expectThrows("schemaVersion mismatch") {
        _ = try WorkbranchListDocument.decode(Data("""
        {"schemaVersion":2,"project":"x","root":"/x","tasks":[]}
        """.utf8))
    }
    try expectThrows("malformed JSON") {
        _ = try WorkbranchListDocument.decode(Data("not json".utf8))
    }

    var tracker = NotificationTracker()
    let empty = MenuState.make(configuredRoots: [], results: [], previous: nil, tracker: &tracker, isBaseline: true)
    try expect(empty.title == "⎇ 0", "empty title")
    try expect(empty.sections.count == 1, "empty section count")
    try expect(empty.sections[0].rows.first?.kind == .message, "empty message row")
    try expect(empty.sections[0].rows.first?.title.contains("config") == true, "empty config guidance")
    try expect(empty.notificationsToSend.isEmpty, "empty notifications")

    let stateDoc = try WorkbranchListDocument.decode(Data("""
    {"schemaVersion":1,"project":"fullstack","root":"/tmp/fullstack","tasks":[
      {"name":"task3","path":"/tmp/fullstack/task3","memoTitle":"draft-tree 가이드 작성","notiCount":2,"repos":[{"name":"backend","branch":"feature/task3","dirty":true}]},
      {"name":"task4","path":"/tmp/fullstack/task4","memoTitle":"","notiCount":0,"repos":[{"name":"backend","branch":"feature/task4","dirty":false}]}
    ]}
    """.utf8))
    let state = MenuState.make(
        configuredRoots: ["/tmp/fullstack", "/tmp/broken"],
        results: [.success(stateDoc), .failure(root: "/tmp/broken", message: "workbranch list failed")],
        previous: nil,
        tracker: &tracker,
        isBaseline: true
    )
    try expect(state.title == "⎇ 2 🔔1", "title with count and notifications")
    try expect(state.sections.count == 2, "section count")
    try expect(state.sections[0].rows[0].title.contains("task3"), "task title")
    try expect(state.sections[0].rows[0].title.contains("🔔2"), "notification marker")
    try expect(state.sections[0].rows[0].title.contains("●"), "dirty marker")
    try expect(state.sections[0].rows[0].primaryAction == .editMemo(root: "/tmp/fullstack", task: "task3"), "primary action")
    try expect(state.sections[1].rows[0].title.contains("workbranch list failed"), "error row")
    try expect(state.notificationsToSend.isEmpty, "baseline no notifications")

    let previousDocument = try WorkbranchListDocument.decode(Data("""
    {"schemaVersion":1,"project":"fullstack","root":"/tmp/fullstack","tasks":[
      {"name":"task3","path":"/tmp/fullstack/task3","memoTitle":"old memo","notiCount":0,"repos":[]}
    ]}
    """.utf8))
    let failedWithPrevious = MenuState.make(
        configuredRoots: ["/tmp/fullstack"],
        results: [.failure(root: "/tmp/fullstack", message: "timeout")],
        previous: ["/tmp/fullstack": previousDocument],
        tracker: &tracker,
        isBaseline: false
    )
    try expect(failedWithPrevious.title == "⎇ 1", "last success title")
    try expect(failedWithPrevious.sections[0].rows[0].title.contains("timeout"), "last success error row")
    try expect(failedWithPrevious.sections[0].rows[1].title.contains("task3"), "last success task row")

    let root = "/tmp/fullstack"
    let initial = try WorkbranchListDocument.decode(Data("""
    {"schemaVersion":1,"project":"fullstack","root":"/tmp/fullstack","tasks":[
      {"name":"task3","path":"/tmp/fullstack/task3","memoTitle":"memo","notiCount":2,"repos":[]}
    ]}
    """.utf8))
    let increased = try WorkbranchListDocument.decode(Data("""
    {"schemaVersion":1,"project":"fullstack","root":"/tmp/fullstack","tasks":[
      {"name":"task3","path":"/tmp/fullstack/task3","memoTitle":"memo","notiCount":3,"repos":[]}
    ]}
    """.utf8))
    let cleared = try WorkbranchListDocument.decode(Data("""
    {"schemaVersion":1,"project":"fullstack","root":"/tmp/fullstack","tasks":[
      {"name":"task3","path":"/tmp/fullstack/task3","memoTitle":"memo","notiCount":0,"repos":[]}
    ]}
    """.utf8))
    var notificationTracker = NotificationTracker()
    let first = MenuState.make(configuredRoots: [root], results: [.success(initial)], previous: nil, tracker: &notificationTracker, isBaseline: true)
    try expect(first.notificationsToSend.isEmpty, "initial baseline no notification")
    let second = MenuState.make(configuredRoots: [root], results: [.success(increased)], previous: [root: initial], tracker: &notificationTracker, isBaseline: false)
    try expect(second.notificationsToSend == [TaskNotification(root: root, task: "task3", count: 3, previousCount: 2)], "increase notification")
    let third = MenuState.make(configuredRoots: [root], results: [.success(cleared)], previous: [root: increased], tracker: &notificationTracker, isBaseline: false)
    try expect(third.notificationsToSend.isEmpty, "clear no notification")
    let fourth = MenuState.make(configuredRoots: [root], results: [.success(increased)], previous: [root: cleared], tracker: &notificationTracker, isBaseline: false)
    try expect(fourth.notificationsToSend == [TaskNotification(root: root, task: "task3", count: 3, previousCount: 0)], "re-increase notification")
}

func runConfigActionsDebounceTests() throws {
    let fm = FileManager.default
    let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("workbranch-companion-tests-\(UUID().uuidString)")
    try fm.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: temp) }

    let configURL = temp.appendingPathComponent("config.json")
    let valid = Data("""
    {"roots":["/tmp/fullstack"],"workbranchBin":"/opt/homebrew/bin/workbranch"}
    """.utf8)
    try valid.write(to: configURL)
    let config = try CompanionConfig.load(from: configURL)
    try expect(config.roots == ["/tmp/fullstack"], "config roots")
    try expect(config.workbranchBin == "/opt/homebrew/bin/workbranch", "workbranch bin")

    try Data("{\"roots\":[\"relative\"]}".utf8).write(to: configURL)
    try expectThrows("relative root rejected") { _ = try CompanionConfig.load(from: configURL) }
    try Data("{\"roots\":[\"/tmp/fullstack\"],\"workbranchBin\":\"bin/workbranch\"}".utf8).write(to: configURL)
    try expectThrows("relative workbranch bin rejected") { _ = try CompanionConfig.load(from: configURL) }
    try Data("not json".utf8).write(to: configURL)
    try expectThrows("invalid json rejected") { _ = try CompanionConfig.load(from: configURL) }
    try fm.removeItem(at: configURL)

    let project = temp.appendingPathComponent("project")
    try fm.createDirectory(at: project, withIntermediateDirectories: true)
    try Data("PROJECT_NAME fullstack\n".utf8).write(to: project.appendingPathComponent(".workbranch.config"))
    let initConfig = CompanionConfig.initSkeleton(currentDirectory: project)
    try expect(initConfig.roots == [project.path], "init skeleton includes cwd project root")
    let guiConfig = try CompanionConfig.ensureGUIConfig(at: configURL)
    try expect(guiConfig.roots == [], "GUI skeleton uses empty roots")
    try expect(fm.fileExists(atPath: configURL.path), "GUI skeleton creates file")

    try expect(TaskNameValidator.isValid("Task_1.2"), "allows CLI safe name")
    try expect(TaskNameValidator.isValid("feat-branch-name"), "allows conventional task folder")
    try expect(!TaskNameValidator.isValid(""), "rejects empty")
    try expect(!TaskNameValidator.isValid("."), "rejects dot")
    try expect(!TaskNameValidator.isValid(".."), "rejects dotdot")
    try expect(!TaskNameValidator.isValid("bad/name"), "rejects slash")
    try expect(!TaskNameValidator.isValid("bad name"), "rejects whitespace")

    let actions = ActionBuilder(workbranchBin: "/opt/homebrew/bin/workbranch")
    try expect(actions.editMemo(root: "/tmp/fullstack", task: "task3", text: "한글 space \"quote\"").arguments == ["memo", "task3", "한글 space \"quote\""], "edit memo argv")
    try expect(actions.editMemo(root: "/tmp/fullstack", task: "task3", text: "").arguments == ["memo", "task3", "--clear"], "empty memo clears")
    try expect(actions.clearNotifications(root: "/tmp/fullstack", task: "task3").arguments == ["noti", "clear", "task3"], "clear noti argv")
    try expect(actions.openTerminal(root: "/tmp/fullstack", task: "task3").arguments == ["terminal", "task3"], "terminal argv")
    try expect(actions.openIDE(root: "/tmp/fullstack", task: "task3").arguments == ["ide", "task3"], "ide argv")
    try expect(actions.revealFinder(root: "/tmp/fullstack", task: "task3").arguments == ["finder", "task3"], "finder argv")
    try expect(actions.copyPath("/tmp/fullstack/task3").executable == "/usr/bin/pbcopy", "copy path executable")
    try expect(actions.copyPath("/tmp/fullstack/task3").standardInput == "/tmp/fullstack/task3", "copy path stdin")
    try expect(actions.add(root: "/tmp/fullstack", task: "Task_1").arguments == ["add", "Task_1"], "add argv")
    try expectThrows("invalid task rejected") { _ = try actions.validatedAdd(root: "/tmp/fullstack", task: "bad/name") }

    let policy = EventFilter()
    try expect(policy.shouldRefresh(forPath: "/tmp/fullstack/task3/TASK-WORKBRANCH.md", root: "/tmp/fullstack"), "task state event refreshes")
    try expect(!policy.shouldRefresh(forPath: "/tmp/fullstack/task3/backend/.git/index", root: "/tmp/fullstack"), "git index ignored")
    try expect(!policy.shouldRefresh(forPath: "/tmp/fullstack/task3/backend/.git", root: "/tmp/fullstack"), "git dir ignored")

    var scheduler = DebounceScheduler(delay: 2.0)
    scheduler.record(root: "/a", at: 0)
    scheduler.record(root: "/a", at: 1)
    scheduler.record(root: "/b", at: 1)
    try expect(scheduler.dueRoots(at: 2.9).isEmpty, "coalesces until newest due")
    try expect(scheduler.dueRoots(at: 3.0) == ["/a", "/b"], "root due order")

    var coordinator = RefreshCoordinator()
    try expect(coordinator.begin(root: "/a"), "first refresh begins")
    try expect(!coordinator.begin(root: "/a"), "second refresh denied")
    coordinator.markPending(root: "/a")
    try expect(coordinator.finish(root: "/a") == .runAgain, "pending requests one more refresh")
    try expect(coordinator.begin(root: "/a"), "follow-up refresh begins")
    try expect(coordinator.finish(root: "/a") == .idle, "no pending after follow-up")
}

do {
    try runModelsAndMenuStateTests()
    try runConfigActionsDebounceTests()
    print("CompanionCoreTestRunner: PASS")
} catch {
    fputs("CompanionCoreTestRunner: FAIL: \(error)\n", stderr)
    exit(1)
}
