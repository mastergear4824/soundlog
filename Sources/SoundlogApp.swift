import SwiftUI

@main
struct SoundlogApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(model)
        }
        .defaultSize(width: 760, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {} // no "New Window"
        }
    }
}
