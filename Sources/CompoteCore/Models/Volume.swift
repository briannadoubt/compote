import Foundation

/// Volume configuration
public struct Volume: Codable, Sendable {
    public let driver: String?
    public let driver_opts: [String: String]?
    public let external: External?
    public let labels: [String: String]?
    public let name: String?

    public init(
        driver: String? = nil,
        driver_opts: [String: String]? = nil,
        external: External? = nil,
        labels: [String: String]? = nil,
        name: String? = nil
    ) {
        self.driver = driver
        self.driver_opts = driver_opts
        self.external = external
        self.labels = labels
        self.name = name
    }
}

