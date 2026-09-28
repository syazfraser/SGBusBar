import Network

/// Reports when the Mac goes offline and comes back, e.g. while Wi-Fi joins after starting up
/// or waking, so times can be fetched as soon as there's a connection.
@MainActor
final class ConnectionMonitor {
    private let monitor = NWPathMonitor()

    /// `onChange` gets true when there's a usable connection, false when there isn't.
    /// It's called once straight away with the current state.
    init(onChange: @escaping @MainActor (Bool) -> Void) {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            MainActor.assumeIsolated { onChange(online) }
        }
        // The main queue keeps the reports in order and on the main actor.
        monitor.start(queue: .main)
    }

    deinit {
        monitor.cancel()
    }
}
