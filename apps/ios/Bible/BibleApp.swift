import SwiftUI

@main
struct BibleApp: App {
    @State private var store = Store()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .task { Breadcrumbs.startIfAsked() }
                #if DEBUG
                    .task { await ReaderStateDebug.followTheReaderIntoBreadcrumbs() }
                #endif
                .environment(store)
                .task {
                    // The search text is built once the first page is up.
                    try? await Task.sleep(for: .milliseconds(300))
                    store.warm()
                }
        }
        .onChange(of: phase) {
            if phase != .active { store.save() }
        }
    }
}
