import Cocoa
import InputMethodKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var server: IMKServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let connectionName = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String,
              let bundleIdentifier = Bundle.main.bundleIdentifier else {
            fatalError("Missing InputMethodKit configuration in Info.plist")
        }

        server = IMKServer(name: connectionName, bundleIdentifier: bundleIdentifier)
        NSApp.setActivationPolicy(.prohibited)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
