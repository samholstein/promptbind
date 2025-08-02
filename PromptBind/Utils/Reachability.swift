import Foundation
import Network

// Network reachability monitor
final class NetworkReachability: ObservableObject {
    @Published var isOnline: Bool = true

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "NetworkReachabilityMonitor")

    static let shared = NetworkReachability()

    private init() {
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = (path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }
}