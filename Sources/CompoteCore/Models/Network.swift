import Foundation

/// Network configuration
public struct Network: Codable, Sendable {
    public let driver: String?
    public let driver_opts: [String: String]?
    public let ipam: IPAMConfig?
    public let external: External?
    public let `internal`: Bool?
    public let attachable: Bool?
    public let labels: [String: String]?
    public let name: String?

    public init(
        driver: String? = nil,
        driver_opts: [String: String]? = nil,
        ipam: IPAMConfig? = nil,
        external: External? = nil,
        `internal`: Bool? = nil,
        attachable: Bool? = nil,
        labels: [String: String]? = nil,
        name: String? = nil
    ) {
        self.driver = driver
        self.driver_opts = driver_opts
        self.ipam = ipam
        self.external = external
        self.`internal` = `internal`
        self.attachable = attachable
        self.labels = labels
        self.name = name
    }
}


/// IPAM configuration
public struct IPAMConfig: Codable, Sendable {
    public let driver: String?
    public let config: [IPAMPoolConfig]?
    public let options: [String: String]?

    public init(
        driver: String? = nil,
        config: [IPAMPoolConfig]? = nil,
        options: [String: String]? = nil
    ) {
        self.driver = driver
        self.config = config
        self.options = options
    }
}

public struct IPAMPoolConfig: Codable, Sendable {
    public let subnet: String?
    public let ip_range: String?
    public let gateway: String?
    public let aux_addresses: [String: String]?

    public init(
        subnet: String? = nil,
        ip_range: String? = nil,
        gateway: String? = nil,
        aux_addresses: [String: String]? = nil
    ) {
        self.subnet = subnet
        self.ip_range = ip_range
        self.gateway = gateway
        self.aux_addresses = aux_addresses
    }
}
