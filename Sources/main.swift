import AppKit

@main
@MainActor
enum PileApp {
    static func main() {
        let app = NSApplication.shared
        let controller = AppController()
        app.delegate = controller
        app.setActivationPolicy(.regular)
        app.run()
    }
}
