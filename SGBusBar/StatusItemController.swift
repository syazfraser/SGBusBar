import AppKit
import SwiftUI

/// The menu bar item. Uses AppKit's NSStatusItem because MenuBarExtra draws its label monochrome,
/// and the times need colour while the rest of the title keeps the menu bar's own text colour.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let store: ArrivalStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    /// What closes the popover; only installed while it's open.
    private var eventMonitors: [Any] = []
    private var resignObserver: NSObjectProtocol?
    /// Where the icon was when the popover last opened, and the check for it moving.
    private var anchorFrame: NSRect = .zero
    private var anchorTimer: Timer?
    private var reanchoring = false
    private var systemAppearanceObservation: NSKeyValueObservation?

    init(store: ArrivalStore, settings: SettingsWindowController) {
        self.store = store
        super.init()

        if let button = statusItem.button {
            let icon = NSImage(systemSymbolName: "bus.fill", accessibilityDescription: "Bus times")
            icon?.isTemplate = true
            button.image = icon
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover)
            // Respond on press, like the system's own menu bar items.
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }

        let actions = DropdownActions(
            addBus: { [weak self] in self?.close(); settings.showAddBus() },
            editStop: { [weak self] code in self?.close(); settings.showStopEditor(for: code) },
            openSettings: { [weak self] in self?.close(); settings.show() }
        )
        let hosting = NSHostingController(rootView: DropdownView(store: store, actions: actions))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        // We decide when it closes (see open()). With .transient, AppKit's own closing raced
        // the toggle, so some clicks on the icon did nothing.
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self
        // Lets the Frosted background run under the little arrow too, instead of stopping short of it.
        popover.hasFullSizeContent = true

        observeStore()
        followTheme()
        systemAppearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.applyTheme() }
        }
    }

    /// Light, Dark, or the Mac's own setting for System. Left alone, a popover takes its look from
    /// the menu bar, which follows the wallpaper rather than the Mac's Light/Dark setting.
    private func applyTheme() {
        popover.appearance = store.theme.appearance ?? NSApp.effectiveAppearance
    }

    /// Re-applies the theme whenever it changes in Settings, even with the popup open.
    private func followTheme() {
        withObservationTracking {
            _ = store.theme
            applyTheme()
        } onChange: { [weak self] in
            Task { @MainActor in self?.followTheme() }
        }
    }

    /// Redraws the title whenever anything it reads from the store changes.
    private func observeStore() {
        withObservationTracking {
            statusItem.button?.attributedTitle = title()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStore() }
        }
        // A new title can resize the item, e.g. switching to Icon only.
        DispatchQueue.main.async { [weak self] in self?.followAnchor() }
    }

    private func title() -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        let result = NSMutableAttributedString()

        func append(_ text: String, color: NSColor? = nil) {
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            if let color { attributes[.foregroundColor] = color }
            result.append(NSAttributedString(string: text, attributes: attributes))
        }

        guard store.hasAPIKey else {
            append(" Set up")
            return result
        }
        guard let bus = store.pinned, store.format.count > 0 else { return result }

        let stale = store.isStale(stop: bus.stopCode)
        let staleColor: NSColor? = stale ? Urgency.stale.nsColor : nil
        append(" \(bus.serviceNo)  ", color: staleColor)

        guard let arrivals = store.arrivals(for: bus) else {
            append("…", color: staleColor)
            return result
        }
        guard !arrivals.isEmpty else {
            append("—", color: staleColor)
            return result
        }

        for (index, arrival) in arrivals.prefix(store.format.count).enumerated() {
            if index > 0 { append(" · ", color: staleColor) }
            let time = store.display(arrival, for: bus)
            append(time.short, color: time.urgency.nsColor)
        }
        if stale { append(" !", color: staleColor) }
        return result
    }

    @objc private func togglePopover() {
        if popover.isShown {
            close()
        } else {
            open()
        }
    }

    private func open() {
        guard let button = statusItem.button else { return }
        applyTheme()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        store.setPopupOpen(true)
        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()

        // The system moves menu bar items (our title changing width, or a neighbour's) without
        // telling the popover, so it would keep pointing at the old spot. Watch for it instead.
        anchorFrame = iconFrameOnScreen
        anchorTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followAnchor() }
        }

        // A click in another app, on the desktop or on another menu bar item.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) {
            eventMonitors.append(monitor)
        }
        // Esc.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.close() }
            return nil
        }) {
            eventMonitors.append(monitor)
        }
        // Switching to another app, e.g. with Cmd-Tab.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func close() {
        popover.performClose(nil)
    }

    private var iconFrameOnScreen: NSRect {
        guard let button = statusItem.button, let window = button.window else { return .zero }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// Re-shows the popover under the icon if the icon has moved. There's no animation, so it just jumps.
    private func followAnchor() {
        guard popover.isShown, let button = statusItem.button else { return }
        let frame = iconFrameOnScreen
        guard frame != anchorFrame else { return }
        anchorFrame = frame
        reanchoring = true
        popover.close()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        reanchoring = false
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        // close() calls this synchronously, including inside followAnchor()'s close-and-show,
        // where the popover is about to reappear and should keep its close triggers.
        guard !reanchoring else { return }
        store.setPopupOpen(false)
        anchorTimer?.invalidate()
        anchorTimer = nil
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resignObserver = nil
    }
}
