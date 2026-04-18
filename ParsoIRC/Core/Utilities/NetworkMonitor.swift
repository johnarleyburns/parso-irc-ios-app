import Foundation
import Network

/// Monitors network reachability using NWPathMonitor.
///
/// Injected into the environment from ParsoIRCApp so any view can
/// react to connectivity changes.
final class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.parso.network-monitor", qos: .utility)

    /// `true` when a usable network path is available.
    @Published private(set) var isConnected: Bool = true

    /// The current interface type (wifi, cellular, wired, etc.).
    @Published private(set) var connectionType: NWInterface.InterfaceType? = nil

    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let type: NWInterface.InterfaceType? = {
                let types: [NWInterface.InterfaceType] = [.wifi, .cellular, .wiredEthernet, .loopback]
                return types.first { path.usesInterfaceType($0) }
            }()
            DispatchQueue.main.async {
                self?.isConnected = connected
                self?.connectionType = type
            }
        }
        monitor.start(queue: queue)
    }

    func stopMonitoring() {
        monitor.cancel()
    }

    deinit {
        stopMonitoring()
    }
}
