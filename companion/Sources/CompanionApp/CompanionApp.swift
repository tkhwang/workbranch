import SwiftUI

@main
struct WorkbranchCompanionApp: App {
    @StateObject private var store = StateStore()

    var body: some Scene {
        MenuBarExtra(store.menuState.title, systemImage: "tray") {
            CompanionPopoverView(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
