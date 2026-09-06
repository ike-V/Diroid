import SwiftUI

@main
struct DiroidApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}
