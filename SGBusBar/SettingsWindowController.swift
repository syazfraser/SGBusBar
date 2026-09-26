import AppKit
import Observation
import SwiftUI

enum SettingsTab: Hashable {
    case general
    case appearance
    case menuBar
    case buses
    case about
}

/// Which page and sheet the Settings window shows, so the popup can open it at the right place.
@MainActor
@Observable
final class SettingsNavigation {
    var tab: SettingsTab = .buses
    var addingBus = false
    var editingStop: StopRef?
}

/// Owns the Settings window. A plain NSWindow because SwiftUI's Settings scene
/// can't be opened reliably from a menu bar app without a Dock icon.
@MainActor
final class SettingsWindowController {
    private let store: ArrivalStore
    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    init(store: ArrivalStore) {
        self.store = store
    }

    func show(tab: SettingsTab? = nil) {
        if let tab { navigation.tab = tab }
        present()
    }

    func showAddBus() {
        navigation.tab = .buses
        navigation.editingStop = nil
        navigation.addingBus = true
        present()
    }

    /// Opens Edit Stop, where you can rename the stop and add or remove its buses.
    func showStopEditor(for stopCode: String) {
        navigation.tab = .buses
        navigation.addingBus = false
        navigation.editingStop = StopRef(code: stopCode)
        present()
    }

    private func present() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(store: store, navigation: navigation))
        // Let SwiftUI own the toolbar and title, so the sidebar and toolbar get Liquid Glass.
        hosting.sceneBridgingOptions = .all
        let window = NSWindow(contentViewController: hosting)
        window.title = "SGBusBar Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 880, height: 620))
        window.center()
        followTheme(of: window)
        return window
    }

    /// Applies the Appearance setting now and whenever it changes.
    private func followTheme(of window: NSWindow) {
        withObservationTracking {
            window.appearance = store.theme.appearance
        } onChange: { [weak self, weak window] in
            Task { @MainActor in
                if let self, let window { self.followTheme(of: window) }
            }
        }
    }
}
