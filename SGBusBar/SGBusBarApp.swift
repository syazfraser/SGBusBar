import SwiftUI

@main
struct SGBusBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The app lives in the menu bar (see StatusItemController); no windows yet.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ArrivalStore?
    private var settings: SettingsWindowController?
    private var statusItem: StatusItemController?

    /// Launched as the host for the unit tests: stay out of the menu bar, the Keychain and the network.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }

        let store = ArrivalStore()
        self.store = store
        let settings = SettingsWindowController(store: store)
        self.settings = settings
        statusItem = StatusItemController(store: store, settings: settings)
        store.start()

        // No polling while the Mac is asleep.
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.store?.stop() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.store?.start() }
        }
    }
}
