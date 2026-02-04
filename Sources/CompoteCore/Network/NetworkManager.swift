import Foundation
import Containerization
import ContainerizationNetlink
import Logging

public enum NetworkError: Error, CustomStringConvertible {
    case failedToCreate(String)
    case failedToConnect(String)
    case notFound(String)

    public var description: String {
        switch self {
        case .failedToCreate(let msg):
            return "Failed to create network: \(msg)"
        case .failedToConnect(let msg):
            return "Failed to connect to network: \(msg)"
        case .notFound(let name):
            return "Network not found: \(name)"
        }
    }
}

/// Manages Docker-style bridge networks
public actor NetworkManager {
    private var networks: [String: NetworkInfo] = [:]
    private let logger: Logger
    private var vmnetNetwork: ContainerManager.Network?

    public struct NetworkInfo: Sendable {
        public let name: String
        public let driver: String
        public let subnet: String
        public let gateway: String
        public var containers: Set<String>
        public let network: ContainerManager.Network?
    }

    public init(logger: Logger) {
        self.logger = logger
    }

    /// Get or create the vmnet network for container manager
    public func getVmnetNetwork() async throws -> ContainerManager.Network? {
        if let network = vmnetNetwork {
            return network
        }

        // Create vmnet network on macOS 26+
        if #available(macOS 26, *) {
            do {
                let network = try ContainerManager.VmnetNetwork()
                vmnetNetwork = network
                logger.info("Created vmnet network")
                return network
            } catch {
                logger.warning("Failed to create vmnet network, containers will have no networking", metadata: [
                    "error": "\(error)"
                ])
                return nil
            }
        } else {
            logger.warning("vmnet networking requires macOS 26+, containers will have no networking")
            return nil
        }
    }

    /// Create a new bridge network
    public func createNetwork(
        name: String,
        driver: String = "bridge",
        subnet: String = "172.20.0.0/16",
        gateway: String = "172.20.0.1"
    ) async throws {
        guard networks[name] == nil else {
            logger.debug("Network already exists", metadata: ["network": "\(name)"])
            return
        }

        logger.info("Creating network", metadata: [
            "network": "\(name)",
            "driver": "\(driver)",
            "subnet": "\(subnet)"
        ])

        do {
            // Get vmnet network for container manager
            let network = try await getVmnetNetwork()

            let info = NetworkInfo(
                name: name,
                driver: driver,
                subnet: subnet,
                gateway: gateway,
                containers: [],
                network: network
            )
            networks[name] = info

            logger.info("Network created", metadata: ["network": "\(name)"])
        } catch {
            logger.error("Failed to create network", metadata: [
                "network": "\(name)",
                "error": "\(error)"
            ])
            throw NetworkError.failedToCreate(error.localizedDescription)
        }
    }

    /// Connect container to network
    public func connectContainer(
        containerID: String,
        networkName: String
    ) async throws -> String {
        guard var info = networks[networkName] else {
            throw NetworkError.notFound(networkName)
        }

        logger.debug("Connecting container to network", metadata: [
            "container": "\(containerID)",
            "network": "\(networkName)"
        ])

        info.containers.insert(containerID)
        networks[networkName] = info

        // Allocate IP address
        let ipAddress = allocateIP(network: info, containerID: containerID)

        logger.info("Container connected to network", metadata: [
            "container": "\(containerID)",
            "network": "\(networkName)",
            "ip": "\(ipAddress)"
        ])

        return ipAddress
    }

    /// Remove network
    public func removeNetwork(name: String) async throws {
        guard let info = networks[name] else {
            logger.debug("Network does not exist", metadata: ["network": "\(name)"])
            return
        }

        guard info.containers.isEmpty else {
            logger.warning("Network still has connected containers", metadata: [
                "network": "\(name)",
                "containers": "\(info.containers.count)"
            ])
            return
        }

        logger.info("Removing network", metadata: ["network": "\(name)"])
        networks.removeValue(forKey: name)
    }

    /// Get network info
    public func getNetwork(name: String) -> NetworkInfo? {
        return networks[name]
    }

    /// List all networks
    public func listNetworks() -> [String: NetworkInfo] {
        return networks
    }

    // Simple IP allocation (incrementing from gateway)
    private func allocateIP(network: NetworkInfo, containerID: String) -> String {
        let baseIP = network.gateway
        let components = baseIP.split(separator: ".")
        guard components.count == 4,
              let lastOctet = Int(components[3]) else {
            return baseIP
        }

        let newIP = "\(components[0]).\(components[1]).\(components[2]).\(lastOctet + network.containers.count + 1)"
        return newIP
    }
}
