import Foundation
import Logging

public enum StateError: Error, CustomStringConvertible {
    case failedToSave(String)
    case failedToLoad(String)
    case invalidState(String)

    public var description: String {
        switch self {
        case .failedToSave(let msg):
            return "Failed to save state: \(msg)"
        case .failedToLoad(let msg):
            return "Failed to load state: \(msg)"
        case .invalidState(let msg):
            return "Invalid state: \(msg)"
        }
    }
}

/// Manages persistent state for containers, networks, and volumes
public actor StateManager {
    private let stateDir: URL
    private let projectName: String
    private let logger: Logger
    private let stateFile: URL

    public struct ProjectState: Codable, Sendable {
        public var containers: [String: ContainerInfo]
        public var networks: [String: NetworkInfo]
        public var volumes: [String: VolumeInfo]

        public init(
            containers: [String: ContainerInfo] = [:],
            networks: [String: NetworkInfo] = [:],
            volumes: [String: VolumeInfo] = [:]
        ) {
            self.containers = containers
            self.networks = networks
            self.volumes = volumes
        }
    }

    public struct ContainerInfo: Codable, Sendable {
        public let id: String
        public let name: String
        public let imageReference: String
        public let createdAt: Date

        public init(id: String, name: String, imageReference: String, createdAt: Date = Date()) {
            self.id = id
            self.name = name
            self.imageReference = imageReference
            self.createdAt = createdAt
        }
    }

    public struct NetworkInfo: Codable, Sendable {
        public let name: String
        public let driver: String
        public let subnet: String
        public let gateway: String

        public init(name: String, driver: String, subnet: String, gateway: String) {
            self.name = name
            self.driver = driver
            self.subnet = subnet
            self.gateway = gateway
        }
    }

    public struct VolumeInfo: Codable, Sendable {
        public let name: String
        public let driver: String
        public let mountPath: String
        public let isExternal: Bool

        public init(name: String, driver: String, mountPath: String, isExternal: Bool) {
            self.name = name
            self.driver = driver
            self.mountPath = mountPath
            self.isExternal = isExternal
        }
    }

    public init(projectName: String, logger: Logger) throws {
        self.projectName = projectName
        self.logger = logger

        // Store state in ~/Library/Application Support/compote/state
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        self.stateDir = appSupport
            .appendingPathComponent("compote")
            .appendingPathComponent("state")

        // Create state directory
        try FileManager.default.createDirectory(
            at: stateDir,
            withIntermediateDirectories: true
        )

        // State file is per-project
        self.stateFile = stateDir.appendingPathComponent("\(projectName).json")
    }

    /// Save project state to disk
    public func save(state: ProjectState) async throws {
        logger.debug("Saving state", metadata: [
            "project": "\(projectName)",
            "containers": "\(state.containers.count)",
            "networks": "\(state.networks.count)",
            "volumes": "\(state.volumes.count)"
        ])

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(state)
            try data.write(to: stateFile)

            logger.info("State saved", metadata: ["file": "\(stateFile.path)"])
        } catch {
            logger.error("Failed to save state", metadata: [
                "error": "\(error)"
            ])
            throw StateError.failedToSave(error.localizedDescription)
        }
    }

    /// Load project state from disk
    public func load() async throws -> ProjectState? {
        guard FileManager.default.fileExists(atPath: stateFile.path) else {
            logger.debug("No state file found", metadata: ["file": "\(stateFile.path)"])
            return nil
        }

        logger.debug("Loading state", metadata: ["file": "\(stateFile.path)"])

        do {
            let data = try Data(contentsOf: stateFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let state = try decoder.decode(ProjectState.self, from: data)

            logger.info("State loaded", metadata: [
                "containers": "\(state.containers.count)",
                "networks": "\(state.networks.count)",
                "volumes": "\(state.volumes.count)"
            ])

            return state
        } catch {
            logger.error("Failed to load state", metadata: [
                "error": "\(error)"
            ])
            throw StateError.failedToLoad(error.localizedDescription)
        }
    }

    /// Clear project state from disk
    public func clear() async throws {
        guard FileManager.default.fileExists(atPath: stateFile.path) else {
            logger.debug("No state file to clear")
            return
        }

        logger.info("Clearing state", metadata: ["file": "\(stateFile.path)"])

        do {
            try FileManager.default.removeItem(at: stateFile)
            logger.info("State cleared")
        } catch {
            logger.error("Failed to clear state", metadata: [
                "error": "\(error)"
            ])
            throw StateError.failedToSave(error.localizedDescription)
        }
    }

    /// Update container in state
    public func updateContainer(info: ContainerInfo) async throws {
        var state = try await load() ?? ProjectState()
        state.containers[info.name] = info
        try await save(state: state)
    }

    /// Remove container from state
    public func removeContainer(name: String) async throws {
        var state = try await load() ?? ProjectState()
        state.containers.removeValue(forKey: name)
        try await save(state: state)
    }

    /// Update network in state
    public func updateNetwork(info: NetworkInfo) async throws {
        var state = try await load() ?? ProjectState()
        state.networks[info.name] = info
        try await save(state: state)
    }

    /// Remove network from state
    public func removeNetwork(name: String) async throws {
        var state = try await load() ?? ProjectState()
        state.networks.removeValue(forKey: name)
        try await save(state: state)
    }

    /// Update volume in state
    public func updateVolume(info: VolumeInfo) async throws {
        var state = try await load() ?? ProjectState()
        state.volumes[info.name] = info
        try await save(state: state)
    }

    /// Remove volume from state
    public func removeVolume(name: String) async throws {
        var state = try await load() ?? ProjectState()
        state.volumes.removeValue(forKey: name)
        try await save(state: state)
    }
}
