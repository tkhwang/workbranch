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
    } catch let error as TestFailure {
        throw error
    } catch {
        return
    }
}

func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}

func runHarnessHelperTests() throws {
    do {
        try expectThrows("outer expectation") {
            throw TestFailure(message: "inner assertion")
        }
        throw TestFailure(message: "expectThrows should rethrow body TestFailure")
    } catch let error as TestFailure {
        try expect(error.message == "inner assertion", "expectThrows preserves TestFailure from body")
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
    try expect(document.tasks[0].planTitle == "", "legacy plan title default")
    try expect(document.tasks[0].notiCount == 2, "noti count")
    try expect(document.tasks[0].status == "", "legacy status default")
    try expect(document.tasks[0].progressDone == 0, "legacy progress done default")
    try expect(document.tasks[0].progressTotal == 0, "legacy progress total default")
    try expect(document.tasks[0].currentItem == "", "legacy current item default")
    try expect(document.tasks[0].updatedAt == 0, "legacy updatedAt default")
    try expect(document.tasks[0].items.isEmpty, "legacy items default")
    try expect(document.tasks[0].repos[0].dirty, "dirty repo")

    let progressDocument = try WorkbranchListDocument.decode(Data("""
    {"schemaVersion":1,"project":"fullstack","root":"/tmp/fullstack","tasks":[
      {"name":"task3","path":"/tmp/fullstack/task3","memoTitle":"draft-tree 가이드 작성","planTitle":"Draft tree rollout","status":"in-progress","progressDone":2,"progressTotal":4,"currentItem":"verify","updatedAt":1760000040,"items":[{"text":"Major","checked":true,"depth":0},{"text":"Child","checked":false,"depth":1}],"notiCount":1,"repos":[]}
    ]}
    """.utf8))
    try expect(progressDocument.tasks[0].status == "in-progress", "progress status decode")
    try expect(progressDocument.tasks[0].planTitle == "Draft tree rollout", "progress plan title decode")
    try expect(progressDocument.tasks[0].progressDone == 2, "progress done decode")
    try expect(progressDocument.tasks[0].progressTotal == 4, "progress total decode")
    try expect(progressDocument.tasks[0].currentItem == "verify", "current item decode")
    try expect(progressDocument.tasks[0].updatedAt == 1760000040, "updatedAt decode")
    try expect(progressDocument.tasks[0].items == [WorkbranchChecklistItem(text: "Major", checked: true, depth: 0), WorkbranchChecklistItem(text: "Child", checked: false, depth: 1)], "items decode")

    let globalDocument = try WorkbranchGlobalDocument.decode(Data("""
    {"schemaVersion":1,"projects":[{"schemaVersion":1,"project":"fullstack","root":"/tmp/fullstack","tasks":[]}],"errors":[{"root":"/tmp/missing","message":"not inside project"}]}
    """.utf8))
    try expect(globalDocument.schemaVersion == 1, "global schema")
    try expect(globalDocument.projects.count == 1, "global projects")
    try expect(globalDocument.errors == [WorkbranchGlobalError(root: "/tmp/missing", message: "not inside project")], "global errors")

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
    try expect(empty.sections[0].rows.first?.primaryAction == .openConfig, "empty config row opens config")
    try expect(empty.notificationsToSend.isEmpty, "empty notifications")

    let stateDoc = try WorkbranchListDocument.decode(Data("""
    {"schemaVersion":1,"project":"fullstack","root":"/tmp/fullstack","tasks":[
      {"name":"task3","path":"/tmp/fullstack/task3","memoTitle":"draft-tree 가이드 작성","status":"in-progress","progressDone":1,"progressTotal":2,"currentItem":"검증 실행","updatedAt":1760000100,"notiCount":2,"repos":[{"name":"backend","branch":"feature/task3","dirty":true}]},
      {"name":"task4","path":"/tmp/fullstack/task4","memoTitle":"","status":"planning","progressDone":0,"progressTotal":0,"currentItem":"","notiCount":0,"repos":[{"name":"backend","branch":"feature/task4","dirty":false}]},
      {"name":"task5","path":"/tmp/fullstack/task5","memoTitle":"","status":"todo","progressDone":0,"progressTotal":2,"currentItem":"설계 시작","notiCount":0,"repos":[{"name":"backend","branch":"feature/task5","dirty":false}]}
    ]}
    """.utf8))
    let state = MenuState.make(
        configuredRoots: ["/tmp/fullstack", "/tmp/broken"],
        results: [.success(stateDoc), .failure(root: "/tmp/broken", message: "workbranch list failed")],
        previous: nil,
        tracker: &tracker,
        isBaseline: true
    )
    try expect(state.title == "▶1 🔔2", "title with in-progress and notifications rollup")
    try expect(state.sections.count == 2, "section count")
    try expect(state.sections[0].rows[0].kind == .task, "task row kind")
    try expect(state.sections[0].rows[0].title.contains("●"), "status icon")
    try expect(state.sections[0].rows[0].title.contains("task3"), "task title")
    try expect(state.sections[0].rows[0].title.contains("🔔2"), "notification marker")
    try expect(state.sections[0].rows[0].title.contains("1/2"), "progress marker")
    try expect(state.sections[0].rows[0].subtitle == "지금: 검증 실행", "current item subtitle")
    try expect(state.sections[0].rows[0].currentItem == "검증 실행", "current item remains primary row data")
    try expect(state.sections[0].rows[0].updatedAt == 1760000100, "updatedAt is embedded in task row")
    try expect(state.sections[0].rows[0].activeTimeText == "", "active time defaults empty")
    try expect(state.sections[0].rows[0].checklistItems.isEmpty, "current item is not mixed into checklist details")
    try expect(state.sections[0].rows[0].isExpandedByDefault, "notified task expands by default")
    try expect(state.sections[0].rows[0].repos[0].name == "backend", "repo embedded in task row")
    try expect(state.sections[0].rows[0].repos[0].branch == "feature/task3", "repo branch embedded in task row")
    try expect(state.sections[0].rows[0].repos[0].dirty, "dirty marker source embedded in task row")
    try expect(state.sections[0].rows[1].kind == .task, "second task row kind")
    try expect(state.sections[0].rows[1].title.contains("○"), "planning status icon")
    try expect(!state.sections[0].rows[1].title.contains("0/0"), "zero-total progress hidden")
    try expect(state.sections[0].rows[1].subtitle == nil, "empty current item hidden")
    try expect(state.sections[0].rows[2].title.contains("·"), "todo status icon")
    try expect(state.sections[0].rows[2].status == "todo", "todo status remains row data")
    try expect(state.sections[0].rows[2].currentItem == "설계 시작", "todo current item remains row data")
    try expect(state.sections[0].rows[0].primaryAction == .editMemo(root: "/tmp/fullstack", task: "task3"), "primary action")
    try expect(state.sections[1].rows[0].title.contains("workbranch list failed"), "error row")
    try expect(state.notificationsToSend.isEmpty, "baseline no notifications")

    let unsortedDocument = try WorkbranchListDocument.decode(Data("""
    {"schemaVersion":1,"project":"sort","root":"/tmp/sort","tasks":[
      {"name":"old","path":"/tmp/sort/old","memoTitle":"","updatedAt":100,"notiCount":0,"repos":[]},
      {"name":"new","path":"/tmp/sort/new","memoTitle":"","updatedAt":300,"notiCount":0,"repos":[]},
      {"name":"tie-first","path":"/tmp/sort/tie-first","memoTitle":"","updatedAt":200,"notiCount":0,"repos":[]},
      {"name":"tie-second","path":"/tmp/sort/tie-second","memoTitle":"","updatedAt":200,"notiCount":0,"repos":[]}
    ]}
    """.utf8))
    let otherSortDocument = try WorkbranchListDocument.decode(Data("""
    {"schemaVersion":1,"project":"other-sort","root":"/tmp/other-sort","tasks":[
      {"name":"other-newest","path":"/tmp/other-sort/other-newest","memoTitle":"","updatedAt":900,"notiCount":0,"repos":[]}
    ]}
    """.utf8))
    let emptySortDocument = try WorkbranchListDocument.decode(Data("""
    {"schemaVersion":1,"project":"empty-sort","root":"/tmp/empty-sort","tasks":[]}
    """.utf8))
    var sortTracker = NotificationTracker()
    let sortedState = MenuState.make(
        configuredRoots: ["/tmp/sort", "/tmp/broken-sort", "/tmp/empty-sort", "/tmp/other-sort"],
        results: [
            .success(unsortedDocument),
            .failure(root: "/tmp/broken-sort", message: "no data"),
            .success(emptySortDocument),
            .success(otherSortDocument),
        ],
        previous: nil,
        tracker: &sortTracker,
        isBaseline: true
    )
    try expect(sortedState.sections.map { $0.root ?? "" } == ["/tmp/other-sort", "/tmp/sort", "/tmp/broken-sort", "/tmp/empty-sort"], "sections sort by latest task updatedAt, then config order for no-data sections")
    try expect(sortedState.sections[1].rows.compactMap(\.taskName) == ["new", "tie-first", "tie-second", "old"], "tasks sort by updatedAt descending with original-order tie break")

    var activeTracker = NotificationTracker()
    let activeState = MenuState.make(
        configuredRoots: ["/tmp/sort"],
        results: [.success(unsortedDocument)],
        previous: nil,
        tracker: &activeTracker,
        isBaseline: true,
        activeSecondsByTask: [ActivityReport.taskKey(root: "/tmp/sort", task: "new"): 4_980]
    )
    try expect(activeState.sections[0].rows[0].taskName == "new", "active time state keeps sort order")
    try expect(activeState.sections[0].rows[0].activeTimeText == "1h23m", "active seconds format as compact hours/minutes")
    try expect(activeState.sections[0].rows[1].activeTimeText == "", "missing active seconds format as empty")
    try expect(ActivityReport.formatDuration(59) == "<1m", "sub-minute duration format")
    try expect(ActivityReport.formatDuration(60) == "1m", "minute duration format")
    try expect(ActivityReport.formatDuration(3_600) == "1h", "hour duration format")

    let readStateDocument = try WorkbranchListDocument.decode(Data("""
    {"schemaVersion":1,"project":"read","root":"/tmp/read","tasks":[
      {"name":"task-read","path":"/tmp/read/task-read","memoTitle":"","updatedAt":100,"notiCount":0,"repos":[]},
      {"name":"task-zero","path":"/tmp/read/task-zero","memoTitle":"","updatedAt":0,"notiCount":0,"repos":[]}
    ]}
    """.utf8))
    var readMarkers = StatusReadMarkers()
    try expect(readMarkers.isEmpty, "empty read markers report empty for first-run baseline")
    try expect(readMarkers.isUnread(root: "/tmp/read", task: "task-read", updatedAt: 100), "empty read markers treat positive updatedAt as unread after baseline")
    try expect(!readMarkers.isUnread(root: "/tmp/read", task: "task-zero", updatedAt: 0), "zero updatedAt is never unread")
    readMarkers.markBaselineRead(documents: [readStateDocument])
    try expect(!readMarkers.isEmpty, "baseline read markers are no longer empty")
    try expect(!readMarkers.isUnread(root: "/tmp/read", task: "task-read", updatedAt: 100), "baseline marks existing status as read")
    try expect(readMarkers.isUnread(root: "/tmp/read", task: "task-read", updatedAt: 101), "larger updatedAt becomes unread after baseline")
    readMarkers.markRead(root: "/tmp/read", task: "task-read", updatedAt: 101)
    try expect(!readMarkers.isUnread(root: "/tmp/read", task: "task-read", updatedAt: 101), "mark read clears current updatedAt")
    try expect(readMarkers.isUnread(root: "/tmp/read", task: "task-read", updatedAt: 102), "future updatedAt becomes unread again")
    try expect(readMarkers.isUnread(root: "/tmp/other-read", task: "task-read", updatedAt: 101), "other root marker is independent")
    try expect(readMarkers.isUnread(root: "/tmp/read", task: "other-task", updatedAt: 101), "other task marker is independent")

    let tempReadStateURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("workbranch-read-state-\(UUID().uuidString)").appendingPathComponent("read-state.json")
    defer { try? FileManager.default.removeItem(at: tempReadStateURL.deletingLastPathComponent()) }
    try readMarkers.write(to: tempReadStateURL)
    let reloadedReadMarkers = try StatusReadMarkers.load(from: tempReadStateURL)
    try expect(reloadedReadMarkers == readMarkers, "read-state JSON round trip")
    let readStateText = try String(contentsOf: tempReadStateURL, encoding: .utf8)
    try expect(readStateText.contains("\"schemaVersion\" : 1") || readStateText.contains("\"schemaVersion\":1"), "read-state JSON writes schemaVersion 1")
    try expect(readStateText.contains("\"roots\""), "read-state JSON writes nested roots map")
    try expect(StatusReadMarkers.loadOrEmpty(from: tempReadStateURL.deletingLastPathComponent().appendingPathComponent("missing.json")) == StatusReadMarkers(), "missing read-state recovers as empty")
    try Data("not json".utf8).write(to: tempReadStateURL)
    try expect(StatusReadMarkers.loadOrEmpty(from: tempReadStateURL) == StatusReadMarkers(), "malformed read-state recovers as empty")

    var unreadTracker = NotificationTracker()
    let unreadState = MenuState.make(
        configuredRoots: ["/tmp/read"],
        results: [.success(readStateDocument)],
        previous: nil,
        tracker: &unreadTracker,
        isBaseline: false,
        statusReadMarkers: StatusReadMarkers()
    )
    try expect(unreadState.sections[0].rows[0].isStatusUnread, "MenuState preserves unread status on row")
    try expect(!unreadState.sections[0].rows[1].isStatusUnread, "MenuState does not mark zero updatedAt unread")
    try expect(unreadState.sections[0].rows[0].statusReadAction == .markStatusRead(root: "/tmp/read", task: "task-read", updatedAt: 100), "task row carries status read action")

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

    let otherPreviousDocument = try WorkbranchListDocument.decode(Data("""
    {"schemaVersion":1,"project":"other","root":"/tmp/other","tasks":[
      {"name":"other-task","path":"/tmp/other/other-task","memoTitle":"","notiCount":0,"repos":[]}
    ]}
    """.utf8))
    let singleRootRefresh = MenuState.make(
        configuredRoots: ["/tmp/fullstack", "/tmp/other"],
        results: [.success(stateDoc)],
        previous: [
            "/tmp/fullstack": previousDocument,
            "/tmp/other": otherPreviousDocument,
        ],
        tracker: &tracker,
        isBaseline: false
    )
    try expect(singleRootRefresh.sections.count == 2, "single-root refresh keeps all sections")
    try expect(singleRootRefresh.sections[1].rows.allSatisfy { $0.kind != .error }, "cached omitted root should not become an error row")
    try expect(singleRootRefresh.sections[1].rows[0].title.contains("other-task"), "cached omitted root keeps previous task")

    let duplicateRootRefresh = MenuState.make(
        configuredRoots: ["/tmp/fullstack", "/tmp/fullstack"],
        results: [.success(stateDoc), .success(stateDoc)],
        previous: nil,
        tracker: &tracker,
        isBaseline: false
    )
    try expect(duplicateRootRefresh.title == "▶1 🔔2", "duplicate root does not double-count tasks")
    try expect(duplicateRootRefresh.sections.count == 1, "duplicate configured root is coalesced")
    try expect(duplicateRootRefresh.sections[0].root == "/tmp/fullstack", "duplicate root keeps first section")

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


func runActivityEventTests() throws {
    let root = "/tmp/fullstack"
    let baseline = try WorkbranchListDocument.decode(Data("""
    {"schemaVersion":1,"project":"fullstack","root":"/tmp/fullstack","tasks":[
      {"name":"task-a","path":"/tmp/fullstack/task-a","memoTitle":"","planTitle":"Checkout plan","status":"planning","progressDone":1,"progressTotal":3,"updatedAt":100,"notiCount":0,"repos":[]}
    ]}
    """.utf8))
    let increased = try WorkbranchListDocument.decode(Data("""
    {"schemaVersion":1,"project":"fullstack","root":"/tmp/fullstack","tasks":[
      {"name":"task-a","path":"/tmp/fullstack/task-a","memoTitle":"","planTitle":"Checkout plan","status":"in-progress","progressDone":2,"progressTotal":3,"updatedAt":160,"notiCount":0,"repos":[]},
      {"name":"task-b","path":"/tmp/fullstack/task-b","memoTitle":"","status":"todo","progressDone":0,"progressTotal":1,"updatedAt":170,"notiCount":0,"repos":[]}
    ]}
    """.utf8))
    let otherRoot = try WorkbranchListDocument.decode(Data("""
    {"schemaVersion":1,"project":"other","root":"/tmp/other","tasks":[
      {"name":"task-a","path":"/tmp/other/task-a","memoTitle":"","status":"review","progressDone":1,"progressTotal":1,"updatedAt":180,"notiCount":0,"repos":[]}
    ]}
    """.utf8))

    try expect(ActivityEvent.diff(previous: [:], next: [baseline], observedAt: 200, isBaseline: true).isEmpty, "baseline does not create activity events")
    try expect(ActivityEvent.diff(previous: [root: baseline], next: [baseline], observedAt: 201, isBaseline: false).isEmpty, "unchanged task creates no event")

    let sameSecondProgress = try WorkbranchListDocument.decode(Data("""
    {"schemaVersion":1,"project":"fullstack","root":"/tmp/fullstack","tasks":[
      {"name":"task-a","path":"/tmp/fullstack/task-a","memoTitle":"","planTitle":"Checkout plan","status":"in-progress","progressDone":2,"progressTotal":3,"updatedAt":100,"notiCount":0,"repos":[]}
    ]}
    """.utf8))
    let sameSecondEvents = ActivityEvent.diff(previous: [root: baseline], next: [sameSecondProgress], observedAt: 205, isBaseline: false)
    try expect(sameSecondEvents == [ActivityEvent(editedAt: 100, observedAt: 205, root: root, project: "fullstack", task: "task-a", planTitle: "Checkout plan", status: "in-progress", progressDone: 2, progressTotal: 3)], "same-second progress/status change creates activity event")

    let events = ActivityEvent.diff(previous: [root: baseline], next: [increased, otherRoot], observedAt: 220, isBaseline: false)
    try expect(events.count == 2, "updated and new tasks under previously seen roots create events")
    try expect(events.contains(ActivityEvent(editedAt: 160, observedAt: 220, root: root, project: "fullstack", task: "task-a", planTitle: "Checkout plan", status: "in-progress", progressDone: 2, progressTotal: 3)), "updated task event captures editedAt, plan, and status")
    try expect(events.contains(ActivityEvent(editedAt: 170, observedAt: 220, root: root, project: "fullstack", task: "task-b", status: "todo", progressDone: 0, progressTotal: 1)), "new non-baseline task under a previously seen root creates event")
    try expect(ActivityEvent.diff(previous: [:], next: [otherRoot], observedAt: 221, isBaseline: false).isEmpty, "root first success after a failed baseline does not backfill existing tasks")

    let encoded = try events[0].jsonLine()
    try expect(encoded.hasSuffix("\n"), "activity event JSONL ends with newline")
    let decoded = try ActivityEvent.decodeLine(encoded)
    try expect(decoded == events[0], "activity event JSON line round trip")
}


func runActivityReportTests() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    func timestamp(year: Int, month: Int, day: Int, hour: Int, minute: Int) throws -> Int {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        guard let date = calendar.date(from: components) else {
            throw TestFailure(message: "timestamp date creation failed")
        }
        return Int(date.timeIntervalSince1970)
    }
    let events = [
        ActivityEvent(editedAt: 1_700_000_100, observedAt: 1_700_000_101, root: "/tmp/a", project: "alpha", task: "task-one", status: "in-progress", progressDone: 1, progressTotal: 2),
        ActivityEvent(editedAt: 1_700_000_700, observedAt: 1_700_000_701, root: "/tmp/a", project: "alpha", task: "task-one", planTitle: "Alpha launch plan", status: "in-progress", progressDone: 2, progressTotal: 2),
        ActivityEvent(editedAt: 1_700_003_000, observedAt: 1_700_003_001, root: "/tmp/a", project: "alpha", task: "task-one", planTitle: "Alpha launch plan", status: "review", progressDone: 2, progressTotal: 2),
        ActivityEvent(editedAt: 1_700_000_400, observedAt: 1_700_000_401, root: "/tmp/b", project: "beta", task: "task-two", status: "planning", progressDone: 0, progressTotal: 1),
    ]
    let report = ActivityReport.make(events: events, scope: .month, generatedAt: 1_700_010_000, calendar: calendar)
    try expect(report.scope == .month, "month report scope")
    try expect(report.projects.count == 2, "report groups by root/project")
    try expect(report.projects[0].root == "/tmp/a", "projects sort by total seconds descending")
    try expect(report.projects[0].tasks[0].seconds == 1_200, "gap-within session plus lead pad")
    try expect(report.projects[0].tasks[0].sessions == 2, "gap-over-idle creates second session")
    try expect(report.projects[0].tasks[0].lastEditedAt == 1_700_003_000, "last edited timestamp")
    try expect(report.projects[0].tasks[0].status == "review", "latest task status is retained for plan detail")
    try expect(report.projects[0].tasks[0].planTitle == "Alpha launch plan", "latest plan title is retained for plan detail")
    try expect(report.projects[0].tasks[0].progressDone == 2, "latest task progress done is retained for plan detail")
    try expect(report.projects[0].tasks[0].progressTotal == 2, "latest task progress total is retained for plan detail")
    try expect(report.projects[1].tasks[0].seconds == 300, "single event receives lead pad")
    try expect(report.totals.seconds == 1_500, "report total seconds")

    let today = ActivityReport.make(events: events, scope: .today, generatedAt: 1_700_005_000, calendar: calendar)
    try expect(today.totals.seconds == 1_500, "today scope includes same UTC day")
    let futureToday = ActivityReport.make(events: events, scope: .today, generatedAt: 1_700_200_000, calendar: calendar)
    try expect(futureToday.totals.seconds == 0, "today scope excludes other days")
    let filtered = ActivityReport.make(events: events, scope: .month, project: "beta", generatedAt: 1_700_005_000, calendar: calendar)
    try expect(filtered.projects.map(\.project) == ["beta"], "project filter")

    let boundaryEvents = [
        ActivityEvent(editedAt: try timestamp(year: 2026, month: 1, day: 1, hour: 23, minute: 55), observedAt: 1, root: "/tmp/boundary", project: "boundary", task: "task", status: "in-progress", progressDone: 1, progressTotal: 2),
        ActivityEvent(editedAt: try timestamp(year: 2026, month: 1, day: 2, hour: 0, minute: 5), observedAt: 2, root: "/tmp/boundary", project: "boundary", task: "task", status: "in-progress", progressDone: 2, progressTotal: 2),
    ]
    let previousDay = ActivityReport.make(events: boundaryEvents, scope: .today, generatedAt: try timestamp(year: 2026, month: 1, day: 1, hour: 12, minute: 0), calendar: calendar)
    let nextDay = ActivityReport.make(events: boundaryEvents, scope: .today, generatedAt: try timestamp(year: 2026, month: 1, day: 2, hour: 12, minute: 0), calendar: calendar)
    try expect(previousDay.totals.seconds == 300, "scope boundary split keeps pre-midnight activity only in previous day")
    try expect(nextDay.totals.seconds == 600, "scope boundary split keeps post-midnight interval and lead pad in next day")

    let parsed = ActivityReport.parseEvents(fromJSONL: """
    {"v":1,"editedAt":1700000100,"observedAt":1700000101,"root":"/tmp/a","project":"alpha","task":"task-one","status":"in-progress","progressDone":1,"progressTotal":2}
    not-json
    {"v":1,"editedAt":1700000400,"observedAt":1700000401,"root":"/tmp/b","project":"beta","task":"task-two","status":"planning","progressDone":0,"progressTotal":1}
    """)
    try expect(parsed.count == 2, "malformed JSONL lines are skipped")
    try expect(ActivityReport.empty(scope: .week, generatedAt: 1).totals.seconds == 0, "empty report has zero total")
    let nextMonth = ActivityReport.make(events: events, scope: .month, generatedAt: 1_702_700_000, calendar: calendar)
    try expect(nextMonth.totals.seconds == 0, "month scope excludes other months")

    let renamedProjectEvents = [
        ActivityEvent(editedAt: 1_700_000_100, observedAt: 1_700_000_101, root: "/tmp/renamed", project: "old-name", task: "task", status: "done", progressDone: 1, progressTotal: 1),
        ActivityEvent(editedAt: 1_700_000_200, observedAt: 1_700_000_201, root: "/tmp/renamed", project: "new-name", task: "task", status: "done", progressDone: 1, progressTotal: 1),
    ]
    let renamedProjectReport = ActivityReport.make(events: renamedProjectEvents, scope: .month, generatedAt: 1_700_005_000, calendar: calendar)
    try expect(renamedProjectReport.projects.count == 2, "same root with different project names remains separate report groups")
    try expect(Set(renamedProjectReport.projects.map(\.identity)).count == 2, "project report identities include project name")

    let midnightEvents = [
        ActivityEvent(editedAt: 1_700_006_300, observedAt: 1_700_006_301, root: "/tmp/m", project: "midnight", task: "task", status: "in-progress", progressDone: 0, progressTotal: 1),
        ActivityEvent(editedAt: 1_700_007_300, observedAt: 1_700_007_301, root: "/tmp/m", project: "midnight", task: "task", status: "in-progress", progressDone: 1, progressTotal: 1),
    ]
    let midnightReport = ActivityReport.make(events: midnightEvents, scope: .month, generatedAt: 1_700_005_000, calendar: calendar)
    try expect(midnightReport.totals.seconds == 1_300, "session duration plus lead pad survives midnight split")
}

func runConfigActionsDebounceTests() throws {
    let fm = FileManager.default
    let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("workbranch-companion-tests-\(UUID().uuidString)")
    try fm.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: temp) }

    let configURL = temp.appendingPathComponent("projects.md")
    let valid = Data("""
    # workbranch companion projects

    workbranchBin: /opt/homebrew/bin/workbranch
    fontName: JetBrains Mono
    fontSize: 14.5
    colorTheme: tokyonight

    ## projects
    - /tmp/fullstack
    """.utf8)
    try valid.write(to: configURL)
    let config = try CompanionConfig.load(from: configURL)
    try expect(config.roots == ["/tmp/fullstack"], "config roots")
    try expect(config.workbranchBin == "/opt/homebrew/bin/workbranch", "workbranch bin")
    try expect(config.font == CompanionFontSettings(name: "JetBrains Mono", size: 14.5), "font settings")
    try expect(config.colorTheme == .tokyonight, "color theme")
    let removedConfig = try config.removingRoot("/tmp/fullstack")
    try expect(removedConfig.roots == [], "remove config root")
    try expect(removedConfig.font == config.font, "remove config root preserves font")
    try expect(removedConfig.colorTheme == config.colorTheme, "remove config root preserves color theme")
    try removedConfig.write(to: configURL)
    let reloadedRemovedConfig = try CompanionConfig.load(from: configURL)
    try expect(reloadedRemovedConfig.roots == [], "remove config root persists")
    try expect(reloadedRemovedConfig.font == config.font, "font settings persist")
    try expect(reloadedRemovedConfig.colorTheme == .tokyonight, "color theme persists")
    try expect(CompanionColorTheme.allCases == [.catppuccin, .dracula, .onedark, .nord, .tokyonight], "selected Superset theme order")
    try expect(CompanionColorTheme.catppuccin.label == "Catppuccin Mocha", "catppuccin label")
    try expect(CompanionColorTheme.onedark.label == "One Dark Pro", "onedark label")
    try expect(CompanionColorTheme.tokyonight.label == "Tokyo Night", "tokyonight label")
    for removedTheme in ["matrix", "amber", "solarized", "green", "blue"] {
        try Data("colorTheme: \(removedTheme)\n\n## projects\n- /tmp/fullstack\n".utf8).write(to: configURL)
        try expectThrows("removed or legacy theme rejected: \(removedTheme)") { _ = try CompanionConfig.load(from: configURL) }
    }

    try Data("## projects\n- relative\n".utf8).write(to: configURL)
    try expectThrows("relative root rejected") { _ = try CompanionConfig.load(from: configURL) }
    try Data("workbranchBin: bin/workbranch\n\n## projects\n- /tmp/fullstack\n".utf8).write(to: configURL)
    try expectThrows("relative workbranch bin rejected") { _ = try CompanionConfig.load(from: configURL) }
    try Data("fontSize: nope\n\n## projects\n- /tmp/fullstack\n".utf8).write(to: configURL)
    try expectThrows("invalid font size rejected") { _ = try CompanionConfig.load(from: configURL) }
    try Data("fontSize: 0\n\n## projects\n- /tmp/fullstack\n".utf8).write(to: configURL)
    try expectThrows("zero font size rejected") { _ = try CompanionConfig.load(from: configURL) }
    try Data("colorTheme: neon\n\n## projects\n- /tmp/fullstack\n".utf8).write(to: configURL)
    try expectThrows("invalid color theme rejected") { _ = try CompanionConfig.load(from: configURL) }
    try fm.removeItem(at: configURL)

    let project = temp.appendingPathComponent("project")
    try fm.createDirectory(at: project, withIntermediateDirectories: true)
    try Data("PROJECT_NAME fullstack\n".utf8).write(to: project.appendingPathComponent(".workbranch.config"))
    let initConfig = CompanionConfig.initSkeleton(currentDirectory: project)
    try expect(initConfig.roots == [project.path], "init skeleton includes cwd project root")
    try expect(ProjectRootSelfHeal.classify(root: project.path) == .available, "existing project root is available")
    try expect(ProjectRootIdentity.matches(configuredRoot: project.path + "/", documentRoot: project.path), "trailing slash configured root matches document root")
    let symlinkRoot = temp.appendingPathComponent("project-link")
    try fm.createSymbolicLink(at: symlinkRoot, withDestinationURL: project)
    try expect(ProjectRootIdentity.matches(configuredRoot: symlinkRoot.path, documentRoot: project.path), "symlink configured root matches canonical document root")
    try expect(!ProjectRootIdentity.matches(configuredRoot: temp.appendingPathComponent("other").path, documentRoot: project.path), "different configured root does not match document root")
    let missingProject = temp.appendingPathComponent("missing-project")
    try expect(ProjectRootSelfHeal.classify(root: missingProject.path) == .trueDeletionCandidate, "missing root with parent is forget candidate")
    let missingParentRoot = temp.appendingPathComponent("missing-parent").appendingPathComponent("project")
    try expect(ProjectRootSelfHeal.classify(root: missingParentRoot.path) == .unavailable, "missing parent is unavailable")
    let taskPath = project.appendingPathComponent("task1")
    try fm.createDirectory(at: taskPath, withIntermediateDirectories: true)
    try fm.removeItem(at: taskPath)
    try expect(ProjectRootSelfHeal.classify(root: project.path) == .available, "task deletion does not remove config root")
    let repoPath = project.appendingPathComponent("task2").appendingPathComponent("repo")
    try fm.createDirectory(at: repoPath, withIntermediateDirectories: true)
    try fm.removeItem(at: repoPath)
    try expect(ProjectRootSelfHeal.classify(root: project.path) == .available, "repo worktree deletion does not remove config root")
    let guiConfig = try CompanionConfig.ensureGUIConfig(at: configURL)
    try expect(guiConfig.roots == [], "GUI skeleton uses empty roots")
    try expect(fm.fileExists(atPath: configURL.path), "GUI skeleton creates file")
    let guiConfigText = try String(contentsOf: configURL, encoding: .utf8)
    try expect(guiConfigText.contains("fontName: Menlo"), "GUI skeleton writes default font name")
    try expect(guiConfigText.contains("fontSize: 13"), "GUI skeleton writes default font size")
    try expect(guiConfigText.contains("colorTheme: dracula"), "GUI skeleton writes default color theme")

    let actions = ActionBuilder(workbranchBin: "/opt/homebrew/bin/workbranch")
    try expect(actions.editMemo(root: "/tmp/fullstack", task: "task3", text: "한글 space \"quote\"").arguments == ["memo", "task3", "한글 space \"quote\""], "edit memo argv")
    try expect(actions.editMemo(root: "/tmp/fullstack", task: "task3", text: "").arguments == ["memo", "task3", "--clear"], "empty memo clears")
    try expect(actions.clearNotifications(root: "/tmp/fullstack", task: "task3").arguments == ["noti", "clear", "task3"], "clear noti argv")
    try expect(actions.openTerminal(root: "/tmp/fullstack", task: "task3").arguments == ["terminal", "task3"], "terminal argv")
    try expect(actions.openIDE(root: "/tmp/fullstack", task: "task3").arguments == ["ide", "task3"], "ide argv")
    try expect(actions.revealFinder(root: "/tmp/fullstack", task: "task3").arguments == ["finder", "task3"], "finder argv")
    try expect(actions.copyPath("/tmp/fullstack/task3").executable == "/usr/bin/pbcopy", "copy path executable")
    try expect(actions.copyPath("/tmp/fullstack/task3").standardInput == "/tmp/fullstack/task3", "copy path stdin")

    let policy = EventFilter()
    try expect(policy.shouldRefresh(forPath: "/tmp/fullstack/task3/TASK-WORKBRANCH.md", root: "/tmp/fullstack"), "task state event refreshes")
    try expect(!policy.shouldRefresh(forPath: "/tmp/fullstack/task3/backend/.git/index", root: "/tmp/fullstack"), "git index ignored")
    try expect(!policy.shouldRefresh(forPath: "/tmp/fullstack/task3/backend/.git", root: "/tmp/fullstack"), "git dir ignored")
    let configPolicy = EventFilter(allowedFileName: "projects.md")
    try expect(configPolicy.shouldRefresh(forPath: "/tmp/workbranch-companion/projects.md", root: "/tmp/workbranch-companion"), "config projects.md event refreshes")
    try expect(!configPolicy.shouldRefresh(forPath: "/tmp/workbranch-companion/read-state.json", root: "/tmp/workbranch-companion"), "read-state write does not refresh config")
    try expect(!configPolicy.shouldRefresh(forPath: "/tmp/workbranch-companion", root: "/tmp/workbranch-companion"), "config directory event does not refresh config")

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

func runProcessRunnerTests() throws {
    let fm = FileManager.default
    let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("workbranch-companion-process-tests-\(UUID().uuidString)")
    try fm.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: temp) }

    let bytes = 1024 * 1024
    let script = """
    import sys
    sys.stdout.write("O" * \(bytes))
    sys.stdout.flush()
    sys.stderr.write("E" * \(bytes))
    sys.stderr.flush()
    """
    let result = try ProcessRunner(timeout: 2).run(
        executable: "/usr/bin/python3",
        arguments: ["-c", script],
        cwd: temp.path
    )
    try expect(!result.timedOut, "large stdout/stderr child should finish without timeout")
    try expect(result.exitCode == 0, "large output child exits cleanly")
    try expect(result.stdout.count == bytes, "large stdout drained while running")
    try expect(result.stderr.count == bytes, "large stderr drained while running")

    let stubbornScript = """
    import signal
    import sys
    import time
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    sys.stdout.write("started\\n")
    sys.stdout.flush()
    sys.stderr.write("still running\\n")
    sys.stderr.flush()
    time.sleep(2)
    """
    let timeoutStart = Date()
    let stubborn = try ProcessRunner(timeout: 0.1).run(
        executable: "/usr/bin/python3",
        arguments: ["-c", stubbornScript],
        cwd: temp.path
    )
    let elapsed = Date().timeIntervalSince(timeoutStart)
    try expect(stubborn.timedOut, "stubborn child reports timeout")
    try expect(elapsed < 1.2, "stubborn child is force-killed after a short graceful timeout")
    try expect(stubborn.exitCode != 0, "force-killed child does not report clean exit")
    try expect(stubborn.stdoutText.contains("started"), "stubborn child stdout is preserved")
    try expect(stubborn.stderrText.contains("still running"), "stubborn child stderr is preserved")
}


func runLoginItemTests() throws {
    let enabled = LoginItemToggleOutcome.resolve(requested: true, statusAfter: .enabled)
    try expect(enabled.launchAtLogin, "enabled status sets launch at login on")
    try expect(enabled.message == "Launch at login enabled", "enabled status message")

    let disabled = LoginItemToggleOutcome.resolve(requested: false, statusAfter: .notRegistered)
    try expect(!disabled.launchAtLogin, "notRegistered status sets launch at login off")
    try expect(disabled.message == "Launch at login disabled", "disabled status message")

    let requiresApproval = LoginItemToggleOutcome.resolve(requested: true, statusAfter: .requiresApproval)
    try expect(!requiresApproval.launchAtLogin, "requiresApproval keeps launch at login off until approval")
    try expect(requiresApproval.message.contains("System Settings"), "requiresApproval points to System Settings")
    try expect(requiresApproval.message.contains("Login Items"), "requiresApproval points to Login Items")

    let failed = LoginItemToggleOutcome.resolve(
        requested: true,
        statusAfter: .notRegistered,
        errorDescription: "Operation not permitted"
    )
    try expect(!failed.launchAtLogin, "failed register remains off")
    try expect(failed.message.contains("failed"), "failed register explains failure")
    try expect(failed.message.contains("Operation not permitted"), "failed register includes error detail")

    let approvalBeatsFailure = LoginItemToggleOutcome.resolve(
        requested: true,
        statusAfter: .requiresApproval,
        errorDescription: "Launch denied"
    )
    try expect(!approvalBeatsFailure.launchAtLogin, "requiresApproval with error remains off")
    try expect(approvalBeatsFailure.message.contains("System Settings"), "requiresApproval takes priority over generic failure")
    try expect(!approvalBeatsFailure.message.contains("failed"), "requiresApproval does not collapse into generic failure")

    let notFound = LoginItemToggleOutcome.resolve(requested: true, statusAfter: .notFound)
    try expect(!notFound.launchAtLogin, "notFound keeps launch at login off")
    try expect(notFound.message.contains("unavailable"), "notFound reports unavailable status")
    try expect(notFound.message.contains("System Settings"), "notFound gives recovery hint")

    enum FakeLoginItemError: Error { case denied }
    final class FakeLoginItemController: LoginItemControlling {
        var status: LoginItemStatus
        var nextStatus: LoginItemStatus?
        var shouldThrow = false

        init(status: LoginItemStatus) {
            self.status = status
        }

        func setEnabled(_ enabled: Bool) throws {
            if shouldThrow { throw FakeLoginItemError.denied }
            status = nextStatus ?? (enabled ? .enabled : .notRegistered)
        }
    }

    let controller = FakeLoginItemController(status: .notRegistered)
    try controller.setEnabled(true)
    try expect(controller.status == .enabled, "fake login item enables")
    try controller.setEnabled(false)
    try expect(controller.status == .notRegistered, "fake login item disables")
    controller.nextStatus = .requiresApproval
    try controller.setEnabled(true)
    try expect(controller.status == .requiresApproval, "fake login item can model approval-required state")
    controller.shouldThrow = true
    try expectThrows("fake login item throws") {
        try controller.setEnabled(true)
    }
}

func runAppSourceInvariantTests() throws {
    let fm = FileManager.default
    let stateStorePath = "Sources/CompanionApp/StateStore.swift"
    let rootWatcherPath = "Sources/CompanionApp/RootWatcher.swift"
    let popoverPath = "Sources/CompanionApp/Views/CompanionPopoverView.swift"
    let rowViewPath = "Sources/CompanionApp/Views/RowView.swift"
    let activityReportViewPath = "Sources/CompanionApp/Views/ActivityReportView.swift"
    let activityRecorderPath = "Sources/CompanionApp/ActivityRecorder.swift"
    let settingsViewPath = "Sources/CompanionApp/Views/AppearanceSettingsView.swift"
    let loginItemControllerPath = "Sources/CompanionApp/LoginItemController.swift"
    let coreLoginItemPath = "Sources/CompanionCore/LoginItem.swift"
    let runnerPath = "Sources/CompanionCoreTestRunner/CompanionCoreTestRunnerTests.swift"
    let stateStore = try String(contentsOfFile: stateStorePath, encoding: .utf8)
    let rootWatcher = try String(contentsOfFile: rootWatcherPath, encoding: .utf8)
    let popover = try String(contentsOfFile: popoverPath, encoding: .utf8)
    let rowView = try String(contentsOfFile: rowViewPath, encoding: .utf8)
    let activityReportView = try String(contentsOfFile: activityReportViewPath, encoding: .utf8)
    let activityRecorder = try String(contentsOfFile: activityRecorderPath, encoding: .utf8)
    let settingsView = try String(contentsOfFile: settingsViewPath, encoding: .utf8)
    let loginItemController = try String(contentsOfFile: loginItemControllerPath, encoding: .utf8)
    let coreLoginItem = try String(contentsOfFile: coreLoginItemPath, encoding: .utf8)
    let runner = try String(contentsOfFile: runnerPath, encoding: .utf8)
    try expect(fm.fileExists(atPath: stateStorePath), "StateStore source exists")
    try expect(fm.fileExists(atPath: rootWatcherPath), "RootWatcher source exists")
    try expect(fm.fileExists(atPath: popoverPath), "popover source exists")
    try expect(fm.fileExists(atPath: rowViewPath), "RowView source exists")
    try expect(fm.fileExists(atPath: activityReportViewPath), "ActivityReportView source exists")
    try expect(fm.fileExists(atPath: activityRecorderPath), "ActivityRecorder source exists")
    try expect(fm.fileExists(atPath: settingsViewPath), "settings source exists")
    try expect(fm.fileExists(atPath: loginItemControllerPath), "login item controller source exists")
    try expect(fm.fileExists(atPath: coreLoginItemPath), "core login item source exists")
    try expect(fm.fileExists(atPath: runnerPath), "runner source exists")
    let cStderrWrite = "fpu" + "ts("
    try expect(!runner.contains(cStderrWrite), "runner avoids C stderr writes that can fail Swift 6 concurrency checks")
    guard
        let initStart = stateStore.range(of: "init(configURL:"),
        let initEnd = stateStore[initStart.lowerBound...].range(of: "static func defaultConfigURL")
    else {
        throw TestFailure(message: "StateStore init body not found")
    }
    let initBody = String(stateStore[initStart.lowerBound..<initEnd.lowerBound])
    try expect(initBody.contains("refreshAll(isBaseline: true)"), "StateStore init triggers initial baseline refresh")
    try expect(initBody.contains("loginItem.status == .enabled"), "StateStore init reads login item status for startup toggle")
    try expect(!popover.contains("store.refreshAll(isBaseline: true)"), "popover appearance does not own startup baseline refresh")
    try expect(stateStore.contains("@Published private(set) var activityReport"), "StateStore publishes activity report")
    try expect(stateStore.contains("weeklyActivityReport"), "StateStore publishes weekly activity report")
    try expect(stateStore.contains("monthlyActivityReport"), "StateStore publishes monthly activity report")
    try expect(!stateStore.contains("allActivityReport"), "StateStore no longer publishes all-time activity report for UI")
    try expect(stateStore.contains("ActivityRecorder"), "StateStore owns activity recorder")
    try expect(stateStore.contains("previousSnapshot = previous"), "StateStore snapshots previous documents before activity diff")
    try expect(stateStore.contains("ActivityEvent.diff"), "StateStore computes activity events during apply")
    try expect(stateStore.contains("activityRecorder.append(events)"), "StateStore appends activity events")
    try expect(stateStore.contains("refreshActivityReport"), "StateStore refreshes activity report after activity changes")
    try expect(activityRecorder.contains("defaultLogURL"), "ActivityRecorder owns default XDG state path")
    try expect(activityRecorder.contains("XDG_STATE_HOME"), "ActivityRecorder honors XDG_STATE_HOME")
    try expect(activityRecorder.contains("activity.jsonl"), "ActivityRecorder writes activity.jsonl")
    try expect(popover.contains("@State private var showingActivityReport"), "popover owns activity report view toggle")
    try expect(popover.contains("if showingActivityReport"), "popover gates report view behind toggle")
    try expect(popover.contains("ActivityReportView(today: store.activityReport, week: store.weeklyActivityReport, month: store.monthlyActivityReport)"), "popover renders activity report in report view")
    try expect(popover.contains("systemName: \"house\""), "footer exposes home icon")
    try expect(popover.contains("systemName: \"chart.bar\""), "footer exposes activity report icon")
    try expect(popover.contains("help: \"Main view\""), "home icon identifies main view")
    guard
        let homeIcon = popover.range(of: "systemName: \"house\""),
        let reportIcon = popover.range(of: "systemName: \"chart.bar\""),
        let settingsIcon = popover.range(of: "Image(systemName: \"gearshape\")")
    else {
        throw TestFailure(message: "footer navigation icon order markers not found")
    }
    try expect(homeIcon.lowerBound < reportIcon.lowerBound && reportIcon.lowerBound < settingsIcon.lowerBound, "footer icons are ordered home, report, settings")
    try expect(popover.contains("showingActivityReport = false"), "settings path can leave activity report view")
    guard
        let reportGateStart = popover.range(of: "if showingActivityReport"),
        let reportGateEnd = popover[reportGateStart.lowerBound...].range(of: "} else {")
    else {
        throw TestFailure(message: "popover report gate body not found")
    }
    let reportGateBody = String(popover[reportGateStart.lowerBound..<reportGateEnd.lowerBound])
    try expect(reportGateBody.contains("ActivityReportView(today: store.activityReport, week: store.weeklyActivityReport, month: store.monthlyActivityReport)"), "activity report is inside report toggle branch")
    try expect(activityReportView.contains("sectionBlock(title: \"Today\""), "ActivityReportView renders Today section")
    try expect(activityReportView.contains("sectionBlock(title: \"Weekly\""), "ActivityReportView renders Weekly section")
    try expect(activityReportView.contains("sectionBlock(title: \"Monthly\""), "ActivityReportView renders Monthly section")
    try expect(activityReportView.contains("sectionSpacing"), "ActivityReportView separates sections with visible spacing")
    try expect(activityReportView.contains("ForEach(report.projects, id: \\.identity)"), "ActivityReportView keys project rows by root and project")
    try expect(activityReportView.contains("planTitleText(task)"), "ActivityReportView renders concrete plan title when available")
    try expect(activityReportView.contains("taskLine(task)"), "ActivityReportView keeps task workspace visible under concrete plan title")
    try expect(activityReportView.contains("statusLine(task)"), "ActivityReportView renders task status detail")
    try expect(activityReportView.contains("│  • plan"), "ActivityReportView labels concrete plan title when present")
    try expect(activityReportView.contains("│  • task"), "ActivityReportView falls back to task workspace when plan title is missing")
    try expect(activityReportView.contains("No activity recorded"), "ActivityReportView has empty state")
    try expect(rowView.contains("row.activeTimeText"), "RowView renders active time text")
    try expect(!rowView.contains("activeTimeColumnWidth"), "RowView does not use fixed-width active-time column")
    try expect(!rowView.contains("emptyActiveTimeColumn"), "task detail rows do not reserve an active-time column")
    try expect(rowView.contains("Text(row.activeTimeText)"), "task command line renders active time inline")
    guard
        let configureStart = stateStore.range(of: "private func configureWatchers()"),
        let configureEnd = stateStore[configureStart.lowerBound...].range(of: "private func startHeartbeat()")
    else {
        throw TestFailure(message: "StateStore configureWatchers body not found")
    }
    let configureBody = String(stateStore[configureStart.lowerBound..<configureEnd.lowerBound])
    try expect(configureBody.contains("configURL.deletingLastPathComponent()"), "config watcher derives config directory")
    try expect(rootWatcher.contains("EventFilter(allowedFileName: configURL.lastPathComponent)"), "config watcher only reacts to projects.md changes")
    guard
        let createDirectoryRange = configureBody.range(of: "createDirectory"),
        let rootWatcherRange = configureBody.range(of: "RootWatcher")
    else {
        throw TestFailure(message: "config watcher creates config directory before installing RootWatcher")
    }
    try expect(createDirectoryRange.lowerBound < rootWatcherRange.lowerBound, "config directory is created before RootWatcher")
    guard
        let refreshAllStart = stateStore.range(of: "func refreshAll(isBaseline:"),
        let refreshAllEnd = stateStore[refreshAllStart.lowerBound...].range(of: "func refresh(root:")
    else {
        throw TestFailure(message: "StateStore refreshAll body not found")
    }
    let refreshAllBody = String(stateStore[refreshAllStart.lowerBound..<refreshAllEnd.lowerBound])
    try expect(!refreshAllBody.contains("listJSON(root:"), "refreshAll does not run per-root CLI refresh synchronously on MainActor")
    try expect(refreshAllBody.contains("refreshGlobalAsync"), "refreshAll uses global list refresh")
    try expect(refreshAllBody.contains("Task {"), "refreshAll schedules async refresh work")
    guard
        let refreshStart = stateStore.range(of: "func refresh(root:"),
        let refreshEnd = stateStore[refreshStart.lowerBound...].range(of: "func noteFilesystemChange")
    else {
        throw TestFailure(message: "StateStore refresh body not found")
    }
    let refreshBody = String(stateStore[refreshStart.lowerBound..<refreshEnd.lowerBound])
    try expect(!refreshBody.contains("listJSON(root:"), "refresh(root:) does not run per-root CLI refresh synchronously on MainActor")
    try expect(refreshBody.contains("refreshAll"), "refresh(root:) delegates to global refresh")
    try expect(stateStore.contains("refreshGlobalAsync"), "StateStore has async global refresh")
    try expect(stateStore.contains("Task.detached"), "CLI global list work is detached from MainActor")
    try expect(stateStore.contains("listGlobalJSON"), "StateStore consumes list --global --json")
    try expect(!stateStore.contains("withTaskGroup"), "global refresh does not run root-by-root task group")
    try expect(!popover.contains("New workspace"), "popover does not expose New workspace UI")
    guard
        let stdinBranchStart = stateStore.range(of: "if let standardInput = command.standardInput"),
        let stdinBranchEnd = stateStore[stdinBranchStart.lowerBound...].range(of: "return")
    else {
        throw TestFailure(message: "StateStore stdin runExternal branch not found")
    }
    let stdinBranch = String(stateStore[stdinBranchStart.lowerBound..<stdinBranchEnd.lowerBound])
    try expect(stdinBranch.contains("runStandardInputExternal"), "stdin branch delegates process work off MainActor")
    try expect(!stdinBranch.contains("waitUntilExit()"), "stdin branch does not wait for process on MainActor")
    try expect(!stdinBranch.contains("fileHandleForWriting.write"), "stdin branch does not write stdin on MainActor")
    try expect(!stdinBranch.contains("process.run()"), "stdin branch does not run process on MainActor")
    try expect(stateStore.contains("private func runStandardInputExternal"), "StateStore has async stdin external runner")
    try expect(stateStore.contains("defaultReadStateURL"), "StateStore has read-state path helper")
    try expect(stateStore.contains("read-state.json"), "StateStore uses read-state.json")
    try expect(stateStore.contains("pendingBaselineStatusReadRoots"), "StateStore tracks per-root pending baseline read roots")
    try expect(!stateStore.contains("shouldBaselineStatusReadMarkers"), "StateStore does not close first-run baselining with a global flag")
    try expect(stateStore.contains("pendingBaselineRoots(configuredRoots:"), "StateStore computes pending baseline roots from configured roots and persisted markers")
    try expect(stateStore.contains("self.pendingBaselineStatusReadRoots = Set(config.roots)"), "StateStore keeps all configured roots pending when read-state is missing")
    try expect(stateStore.contains("!markers.roots.keys.contains"), "StateStore leaves roots without persisted markers pending")
    try expect(stateStore.contains("pendingBaselineStatusReadRoots.remove(document.root)"), "StateStore clears baseline pending only for successful roots")
    try expect(stateStore.contains("statusReadMarkers.markBaselineRead"), "StateStore baselines existing tasks as read")
    try expect(stateStore.contains("markStatusRead"), "StateStore exposes markStatusRead action")
    try expect(stateStore.contains("statusReadMarkers.write"), "StateStore persists read markers")
    try expect(stateStore.contains("lastRefreshResults"), "StateStore tracks the last refresh results")
    try expect(stateStore.contains("lastRefreshResults = results"), "StateStore updates last refresh results after refresh apply")
    guard
        let rebuildStart = stateStore.range(of: "private func rebuildMenuStateFromPrevious()"),
        let rebuildEnd = stateStore[rebuildStart.lowerBound...].range(of: "func openConfig()")
    else {
        throw TestFailure(message: "StateStore rebuildMenuStateFromPrevious body not found")
    }
    let rebuildBody = String(stateStore[rebuildStart.lowerBound..<rebuildEnd.lowerBound])
    try expect(rebuildBody.contains("results: lastRefreshResults"), "status read rebuild preserves current refresh errors")
    try expect(!rebuildBody.contains("results: []"), "status read rebuild does not drop current refresh errors")
    guard
        let sectionForEachStart = popover.range(of: "ForEach(store.menuState.sections"),
        let rowForEachStart = popover.range(of: "ForEach(section.rows")
    else {
        throw TestFailure(message: "popover uses stable model ids for section and row ForEach")
    }
    let sectionPrefix = String(popover[..<sectionForEachStart.lowerBound])
    let rowPrefix = String(popover[..<rowForEachStart.lowerBound])
    try expect(!sectionPrefix.contains("store.menuState.sections.enumerated()"), "section ForEach does not use offset ids")
    try expect(!rowPrefix.contains("section.rows.enumerated()"), "row ForEach does not use offset ids")
    try expect(popover.contains("ForEach(store.menuState.sections)"), "section ForEach uses Identifiable sections")
    try expect(popover.contains("ForEach(section.rows)"), "row ForEach uses Identifiable rows")
    try expect(!popover.contains(".sheet(isPresented:"), "settings are inline, not transient sheet")
    try expect(popover.contains("if showingSettings"), "popover keeps settings panel inline while open")
    guard
        let saveSettingsStart = popover.range(of: "private func saveSettings()"),
        let saveSettingsEnd = popover[saveSettingsStart.lowerBound...].range(of: "private func applyTheme")
    else {
        throw TestFailure(message: "saveSettings body not found")
    }
    let saveSettingsBody = String(popover[saveSettingsStart.lowerBound..<saveSettingsEnd.lowerBound])
    try expect(saveSettingsBody.contains("if store.saveAppearance"), "Settings close only after a successful save")
    try expect(saveSettingsBody.contains("colorTheme: draftColorTheme"), "Save persists the selected draft theme")
    try expect(saveSettingsBody.contains("showingSettings = false"), "successful Save closes settings")
    guard
        let saveAppearanceStart = stateStore.range(of: "func saveAppearance"),
        let saveAppearanceEnd = stateStore[saveAppearanceStart.lowerBound...].range(of: "func saveColorTheme")
    else {
        throw TestFailure(message: "StateStore saveAppearance body not found")
    }
    let saveAppearanceBody = String(stateStore[saveAppearanceStart.lowerBound..<saveAppearanceEnd.lowerBound])
    try expect(saveAppearanceBody.contains("-> Bool"), "saveAppearance reports success or failure")
    try expect(saveAppearanceBody.contains("return true"), "saveAppearance returns true after config write succeeds")
    try expect(saveAppearanceBody.contains("return false"), "saveAppearance returns false after config write fails")
    try expect(stateStore.contains("@Published private(set) var launchAtLogin"), "StateStore publishes launch at login state")
    try expect(stateStore.contains("func setLaunchAtLogin"), "StateStore exposes launch at login setter")
    try expect(stateStore.contains("loginItem: LoginItemControlling"), "StateStore receives login item controller")
    try expect(stateStore.contains("loginItem.status"), "StateStore reads login item status")
    try expect(stateStore.contains("LoginItemToggleOutcome.resolve"), "StateStore resolves login item status messages through Core")
    guard
        let applyThemeStart = popover.range(of: "private func applyTheme"),
        let applyThemeEnd = popover[applyThemeStart.lowerBound...].range(of: "\\n    }\\n}", options: .regularExpression)
    else {
        throw TestFailure(message: "applyTheme body not found")
    }
    let applyThemeBody = String(popover[applyThemeStart.lowerBound..<applyThemeEnd.lowerBound])
    try expect(applyThemeBody.contains("draftColorTheme = theme"), "theme selection updates draft state")
    try expect(!applyThemeBody.contains("store.save"), "theme selection does not persist before Save")
    try expect(popover.contains("workbranch-companion"), "popover header uses companion app name")
    try expect(popover.contains("status monitor"), "popover header states companion status monitor role")
    guard
        let headerStart = popover.range(of: "private var header"),
        let headerEnd = popover[headerStart.lowerBound...].range(of: "private func sectionView")
    else {
        throw TestFailure(message: "header body not found")
    }
    let headerBody = String(popover[headerStart.lowerBound..<headerEnd.lowerBound])
    try expect(headerBody.contains("Text(companionVersionText)"), "header renders version text on the right")
    try expect(popover.contains("Bundle.main.object(forInfoDictionaryKey: \"CFBundleShortVersionString\")"), "version text reads app bundle short version")
    try expect(popover.contains("0.0.0-dev"), "version text has local development fallback")
    try expect(!headerBody.contains("IconControl"), "header does not render refresh or quit controls")
    try expect(!popover.contains("\"$ refresh\""), "refresh command text is not rendered in header")
    try expect(!popover.contains("\"$ refresh-now\""), "refresh command text is not rendered in footer")
    try expect(!popover.contains("\"$ quit\""), "quit command text is not rendered")
    try expect(popover.contains("arrow.clockwise"), "refresh action is icon-only")
    try expect(popover.contains("power"), "quit action is icon-only")
    try expect(popover.contains("TerminalLine(prefix: \"#\", command: store.statusMessage"), "status message renders in footer")
    try expect(!popover.contains("section.root"), "project path is not rendered in simplified companion view")
    try expect(!popover.contains("store.menuState.title"), "header does not render aggregate task counters")
    try expect(popover.contains("RowView(row: row, store: store)"), "row view receives store for non-task primary actions")
    try expect(popover.contains(".frame(width: 560, height: 720)"), "popover default height is 720")
    try expect(rowView.contains("taskBlock"), "task rows render as a fixed meta block")
    try expect(!rowView.contains("DisclosureGroup"), "task rows do not add a parent disclosure row")
    try expect(!rowView.contains("State(initialValue: true)"), "status details are rendered directly without a parent progress row")
    try expect(!rowView.contains("Text(\"progress\")"), "task rows do not render a progress parent label")
    try expect(rowView.contains("ScrollView(.vertical)"), "status details are scrollable")
    try expect(rowView.contains(".frame(maxHeight:"), "status details have a bounded height")
    try expect(!rowView.contains("private var statusSummaryLine"), "status details do not duplicate the primary status line")
    try expect(rowView.contains("row.progressDone") && rowView.contains("row.progressTotal"), "primary status message can include progress counts")
    try expect(!rowView.contains(".padding(.leading, 13)"), "status details align with repo and branch guide lines")
    try expect(!rowView.contains("TextField(\"memo text\""), "task rows do not expose memo editing")
    try expect(rowView.contains("detailLine(label: \"memo\""), "task rows render list --global memoTitle in the detail area")
    try expect(rowView.contains("row.checklistItems"), "task rows render TASK-WORKBRANCH status items")
    try expect(rowView.contains("statusItemLine"), "task status content renders as checklist lines")
    try expect(rowView.contains("currentWorkLine"), "task rows render current work as a primary fixed line")
    try expect(rowView.contains("statusReadAction"), "current work line owns status-read action")
    try expect(rowView.contains("store.perform(statusReadAction)"), "current work line click marks status read")
    try expect(rowView.contains("row.isStatusUnread"), "current work line renders unread state")
    try expect(rowView.contains("\"● \\(text)\""), "current work line renders a compact unread dot affordance")
    guard let currentWorkLineRange = rowView.range(of: "currentWorkLine"), let detailsRange = rowView.range(of: "statusDetailsBlock") else {
        throw TestFailure(message: "current work line or status details block not found")
    }
    try expect(currentWorkLineRange.lowerBound < detailsRange.lowerBound, "current work line is defined before detail block")
    guard let taskCommandStart = rowView.range(of: "private var taskCommandLine"), let taskCommandEnd = rowView[taskCommandStart.lowerBound...].range(of: "private var messageLine") else {
        throw TestFailure(message: "task command line body not found")
    }
    let taskCommandBody = String(rowView[taskCommandStart.lowerBound..<taskCommandEnd.lowerBound])
    try expect(!taskCommandBody.contains("statusLabel"), "task command line does not duplicate status")
    guard let statusLineStart = rowView.range(of: "private var currentWorkLineContent"), let statusLineEnd = rowView[statusLineStart.lowerBound...].range(of: "private var statusDetailsBlock") else {
        throw TestFailure(message: "current work line content body not found")
    }
    let statusLineBody = String(rowView[statusLineStart.lowerBound..<statusLineEnd.lowerBound])
    try expect(statusLineBody.contains("Text(\"│\")"), "primary status line uses pipe separators")
    try expect(statusLineBody.contains("statusSegmentText"), "primary status line renders status segment")
    try expect(statusLineBody.contains("timeSegmentText"), "primary status line renders time segment")
    try expect(statusLineBody.contains("statusMessageText"), "primary status line renders message segment")
    try expect(rowView.contains("if let primaryAction = row.primaryAction"), "non-task primary actions remain clickable")
    try expect(rowView.contains("store.perform(primaryAction)"), "message primary action invokes StateStore")
    try expect(!rowView.contains("startPrimaryAction"), "task rows do not trigger primary actions on click")
    try expect(!rowView.contains("Menu(\"actions\")"), "task rows do not render action menus")
    try expect(!rowView.contains("status now="), "task rows do not render current checklist item")
    try expect(!rowView.contains("command: \"checklist\""), "task rows do not render checklist labels")
    try expect(!rowView.contains("label: \"progress\""), "task rows do not render progress tokens")
    try expect(!rowView.contains("label: \"noti\""), "task rows do not render notification tokens")
    try expect(rowView.contains("label: \"branch\""), "repo rows render branch tokens")
    try expect(!rowView.contains("label: \"dirty\""), "repo rows do not render dirty tokens")
    try expect(!rowView.contains("repo.dirty ? \"yes\" : \"no\""), "dirty token is not rendered beside branch")
    try expect(rowView.contains("statusLabel.uppercased()"), "primary status line uppercases the status label")
    try expect(rowView.contains("updatedTimeText"), "primary status line includes update time helper")
    try expect(rowView.contains("dateFormat = \"HH:mm\""), "status update time is hour-minute only")
    try expect(rowView.contains("palette.warning"), "primary status line uses warm color")
    try expect(!rowView.contains("RoundedRectangle(cornerRadius: 4)"), "primary status text no longer uses old stroke box")
    try expect(!rowView.contains(".padding(.horizontal, 7)"), "primary status text no longer keeps box padding")
    try expect(settingsView.contains("Text(fontName)"), "settings font selector renders selected font with custom text")
    try expect(settingsView.contains("foregroundStyle(palette.text)"), "settings selected font text uses terminal palette text color")
    try expect(settingsView.contains("Button { fontName = name }"), "settings font selector remains interactive")
    try expect(settingsView.contains("FixedWidthFontCatalog.names"), "settings font picker uses fixed-width font catalog")
    try expect(settingsView.contains("fixedPitchFontMask"), "fixed-width font catalog filters system monospaced fonts")
    try expect(settingsView.contains("selectedTheme"), "settings view separates selected theme")
    try expect(settingsView.contains("candidateThemes"), "settings view computes four candidate themes")
    try expect(settingsView.contains("CompanionColorTheme.allCases.filter { $0 != colorTheme }"), "candidate themes exclude selected theme")
    try expect(settingsView.contains("Text(\"Selected theme\")"), "settings view labels selected theme")
    try expect(settingsView.contains("Text(\"Candidate themes\")"), "settings view labels candidate themes")
    try expect(settingsView.contains("onThemeChange(theme)"), "theme tile invokes live theme change callback")
    try expect(settingsView.contains("@Binding var launchAtLogin"), "settings view receives launch at login binding")
    try expect(settingsView.contains("Toggle(isOn: $launchAtLogin)"), "settings view renders launch at login toggle")
    try expect(settingsView.contains("Launch at login"), "settings view labels launch at login toggle")
    try expect(popover.contains("store.launchAtLogin"), "popover binds settings toggle to store login item state")
    try expect(popover.contains("store.setLaunchAtLogin"), "popover writes settings toggle through store login item setter")
    guard
        let openSettingsStart = popover.range(of: "private func openSettings()"),
        let openSettingsEnd = popover[openSettingsStart.lowerBound...].range(of: "private func saveSettings()")
    else {
        throw TestFailure(message: "openSettings body not found")
    }
    let openSettingsBody = String(popover[openSettingsStart.lowerBound..<openSettingsEnd.lowerBound])
    try expect(!openSettingsBody.contains("launchAtLogin"), "openSettings does not copy launch at login into draft state")
    try expect(!saveSettingsBody.contains("launchAtLogin"), "saveSettings does not persist launch at login through config")
    try expect(loginItemController.contains("struct SMAppServiceLoginItemController"), "login item controller is value-type system glue")
    try expect(loginItemController.contains("import ServiceManagement"), "login item controller imports ServiceManagement")
    try expect(loginItemController.contains("SMAppService.mainApp"), "login item controller uses SMAppService.mainApp")
    try expect(loginItemController.contains("register()"), "login item controller registers main app")
    try expect(loginItemController.contains("unregister()"), "login item controller unregisters main app")
    try expect(loginItemController.contains(".requiresApproval"), "login item controller maps requiresApproval status")
    try expect(loginItemController.contains("@unknown default"), "login item controller handles future SMAppService statuses")
    try expect(coreLoginItem.contains("enum LoginItemStatus"), "core login item defines status enum")
    try expect(coreLoginItem.contains("protocol LoginItemControlling"), "core login item defines controller protocol")
    try expect(coreLoginItem.contains("var status: LoginItemStatus"), "core login item protocol preserves full status")
    try expect(coreLoginItem.contains("func resolve("), "core login item defines pure outcome resolver")
    try expect(!coreLoginItem.contains("import ServiceManagement"), "core login item remains ServiceManagement-free")
}

@main
struct CompanionCoreTestRunnerTests {
    static func main() {
        do {
            try runHarnessHelperTests()
            try runModelsAndMenuStateTests()
            try runActivityEventTests()
            try runActivityReportTests()
            try runConfigActionsDebounceTests()
            try runProcessRunnerTests()
            try runLoginItemTests()
            try runAppSourceInvariantTests()
            print("CompanionCoreTestRunner: PASS")
        } catch {
            writeStandardError("CompanionCoreTestRunner: FAIL: \(error)\n")
            exit(1)
        }
    }
}
