import Foundation
import Network

struct DiscoveredPostgres: Identifiable, Hashable, Sendable {
    var id: Int { port }
    let host: String
    let port: Int
}

struct PostgresDiscoveryService: Sendable {
    private let commonPorts = [5432, 5433, 5434, 5435, 6543]

    func discover() async -> [DiscoveredPostgres] {
        await withTaskGroup(of: DiscoveredPostgres?.self) { group in
            for port in commonPorts {
                group.addTask {
                    guard await probe(port: port) else { return nil }
                    return DiscoveredPostgres(host: "localhost", port: port)
                }
            }

            var discoveries: [DiscoveredPostgres] = []
            for await discovery in group {
                if let discovery { discoveries.append(discovery) }
            }
            return discoveries.sorted { $0.port < $1.port }
        }
    }

    private func probe(port: Int) async -> Bool {
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }

        return await withCheckedContinuation { continuation in
            let probe = PostgresProbe(continuation: continuation)
            let connection = NWConnection(host: .ipv4(.loopback), port: endpointPort, using: .tcp)
            probe.connection = connection
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // PostgreSQL responds to an SSLRequest with one byte: S or N.
                    connection.send(content: Data([0, 0, 0, 8, 4, 210, 22, 47]), completion: .contentProcessed { error in
                        if error != nil { probe.finish(false); return }
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { data, _, _, _ in
                            probe.finish(data?.first == Character("S").asciiValue || data?.first == Character("N").asciiValue)
                        }
                    })
                case .failed, .cancelled:
                    probe.finish(false)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.8) {
                probe.finish(false)
            }
        }
    }
}

private final class PostgresProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    var connection: NWConnection?

    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func finish(_ result: Bool) {
        lock.lock()
        guard let continuation else { lock.unlock(); return }
        self.continuation = nil
        lock.unlock()
        connection?.cancel()
        continuation.resume(returning: result)
    }
}
