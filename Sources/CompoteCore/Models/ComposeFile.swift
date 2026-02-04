import Foundation

/// Top-level docker-compose/compote configuration file
public struct ComposeFile: Codable, Sendable {
    public let version: String?
    public let services: [String: Service]
    public let networks: [String: Network]?
    public let volumes: [String: Volume]?
    public let configs: [String: Config]?
    public let secrets: [String: Secret]?

    public init(
        version: String? = nil,
        services: [String: Service],
        networks: [String: Network]? = nil,
        volumes: [String: Volume]? = nil,
        configs: [String: Config]? = nil,
        secrets: [String: Secret]? = nil
    ) {
        self.version = version
        self.services = services
        self.networks = networks
        self.volumes = volumes
        self.configs = configs
        self.secrets = secrets
    }
}

/// Configuration file reference
public struct Config: Codable, Sendable {
    public let file: String?
    public let external: Bool?
    public let name: String?

    public init(file: String? = nil, external: Bool? = nil, name: String? = nil) {
        self.file = file
        self.external = external
        self.name = name
    }
}

/// Secret file reference
public struct Secret: Codable, Sendable {
    public let file: String?
    public let external: Bool?
    public let name: String?

    public init(file: String? = nil, external: Bool? = nil, name: String? = nil) {
        self.file = file
        self.external = external
        self.name = name
    }
}
