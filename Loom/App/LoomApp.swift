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
        MenuBarExtra {
            MenuBarRootView(store: store)
        } label: {
            Image(nsImage: LoomIcon.menuBarImage)
        }
        .menuBarExtraStyle(.window)
    }
}
