import SwiftUI

@main
struct DiroidApp: App {
    @AppStorage(Zoom.key) private var zoomScale = 1.0
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .newItem) {
                Button("Test GUI") { openWindow(id: "files-test") }
            }
            CommandGroup(after: .toolbar) {
                Button("Zoom In") { zoomScale = Zoom.adjusted(zoomScale, by: Zoom.step) }
                    .keyboardShortcut("+")
                    .disabled(zoomScale >= Zoom.range.upperBound)
                Button("Zoom Out") { zoomScale = Zoom.adjusted(zoomScale, by: -Zoom.step) }
                    .keyboardShortcut("-")
                    .disabled(zoomScale <= Zoom.range.lowerBound)
                Button("Actual Size") { zoomScale = 1.0 }
                    .keyboardShortcut("0")
                    .disabled(zoomScale == 1.0)
            }
        }

        Window("Diroid Files (Test)", id: "files-test") {
            FileBrowserTestView()
        }
    }
}
