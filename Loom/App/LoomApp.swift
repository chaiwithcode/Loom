import SwiftUI
import LoomCore

@main
struct LoomApp: App {
    @State private var store: SessionStore

    init() {
        let fixture = DemoFixture.resolve()
        let providers = fixture.makeProviders()
        _store = State(initialValue: SessionStore(providers: providers))
    }

    var body: some Scene {
        MenuBarExtra("Loom", systemImage: "circle.grid.2x2.fill") {
            MenuBarRootView(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
