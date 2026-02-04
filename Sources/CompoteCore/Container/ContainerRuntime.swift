import Foundation
import Containerization
import Logging

public enum ContainerError: Error, CustomStringConvertible {
    case failedToStart(String)
    case failedToStop(String)
    case notRunning(String)
    case execFailed(String)
    case notImplemented(String)
    case configurationError(String)

    public var description: String {
        switch self {
        case .failedToStart(let msg):
            return "Failed to start container: \(msg)"
        case .failedToStop(let msg):
            return "Failed to stop container: \(msg)"
        case .notRunning(let id):
            return "Container is not running: \(id)"
        case .execFailed(let msg):
            return "Failed to execute command: \(msg)"
        case .notImplemented(let msg):
            return "Not yet implemented: \(msg)"
        case .configurationError(let msg):
            return "Configuration error: \(msg)"
        }
    }
}

/// Wrapper around ContainerManager for managing container lifecycle
public actor ContainerRuntime {
    public let id: String
    public let name: String
    private let logger: Logger
    private var containerManager: ContainerManager
    private var container: LinuxContainer?
    private var isRunning = false
    private var imageReference: String?
    private let stdoutBuffer = LogBuffer()
    private let stderrBuffer = LogBuffer()

    public init(
        id: String,
        name: String,
        containerManager: ContainerManager,
        logger: Logger
    ) {
        self.id = id
        self.name = name
        self.containerManager = containerManager
        self.logger = logger
    }

    /// Create and start container with given image reference and configuration
    public func start(
        imageReference: String,
        rootfsSizeInBytes: UInt64 = 2048 * 1024 * 1024, // 2GB default
        readOnly: Bool = false,
        configuration: LinuxContainer.Configuration
    ) async throws {
        logger.info("Creating container", metadata: [
            "container": "\(name)",
            "image": "\(imageReference)"
        ])

        self.imageReference = imageReference

        // Capture log buffers outside the closure to avoid actor isolation issues
        let stdoutWriter = BufferedWriter(buffer: stdoutBuffer)
        let stderrWriter = BufferedWriter(buffer: stderrBuffer)

        // Create container with configuration closure
        // Note: containerManager.create() is mutating, so we need to use a local var
        var manager = self.containerManager
        let container = try await manager.create(
            id,
            reference: imageReference,
            rootfsSizeInBytes: rootfsSizeInBytes,
            readOnly: readOnly
        ) { config in
            // Copy configuration from LinuxContainer.Configuration
            config.cpus = configuration.cpus
            config.memoryInBytes = configuration.memoryInBytes
            config.hostname = configuration.hostname

            // Process configuration
            config.process.arguments = configuration.process.arguments
            config.process.environmentVariables = configuration.process.environmentVariables
            config.process.workingDirectory = configuration.process.workingDirectory
            config.process.user = configuration.process.user
            config.process.capabilities = configuration.process.capabilities
            config.process.terminal = configuration.process.terminal

            // Mounts (rootfs + volumes)
            config.mounts = configuration.mounts

            // Networking
            config.interfaces = configuration.interfaces
            config.dns = configuration.dns
            config.hosts = configuration.hosts

            // Boot log
            config.bootLog = configuration.bootLog

            // Capture stdout/stderr for log streaming
            config.process.stdout = stdoutWriter
            config.process.stderr = stderrWriter
        }

        logger.info("Container created, starting VM", metadata: ["container": "\(name)"])

        // Create VM resources
        try await container.create()

        // Start container process
        try await container.start()

        // Store references
        self.containerManager = manager
        self.container = container
        self.isRunning = true

        logger.info("Container started", metadata: ["container": "\(name)"])
    }

    /// Stop the container gracefully
    public func stop(timeout: Duration = .seconds(10)) async throws {
        guard let container = self.container else {
            logger.warning("Container not running", metadata: ["container": "\(name)"])
            return
        }

        logger.info("Stopping container", metadata: ["container": "\(name)"])

        do {
            try await container.stop()
            self.isRunning = false
            self.container = nil

            // Close log buffers
            await stdoutBuffer.close()
            await stderrBuffer.close()

            logger.info("Container stopped", metadata: ["container": "\(name)"])
        } catch {
            logger.error("Failed to stop container", metadata: [
                "container": "\(name)",
                "error": "\(error)"
            ])
            throw ContainerError.failedToStop(error.localizedDescription)
        }
    }

    /// Delete the container and clean up resources
    public func delete() async throws {
        // Stop if running
        if isRunning {
            try await stop()
        }

        // Delete container from manager
        do {
            var manager = self.containerManager
            try await manager.delete(id)
            self.containerManager = manager
            logger.info("Container deleted", metadata: ["container": "\(name)"])
        } catch {
            logger.error("Failed to delete container", metadata: [
                "container": "\(name)",
                "error": "\(error)"
            ])
            throw ContainerError.failedToStop(error.localizedDescription)
        }
    }

    /// Wait for container to exit and return exit code
    public func wait() async throws -> Int32 {
        guard let container = self.container else {
            throw ContainerError.notRunning(id)
        }

        let exitStatus = try await container.wait()
        isRunning = false
        return exitStatus.exitCode
    }

    /// Get container running state
    public func getIsRunning() -> Bool {
        return isRunning
    }

    /// Execute command in running container
    public func exec(
        command: [String],
        environment: [String: String] = [:]
    ) async throws -> Int32 {
        guard let container = self.container else {
            throw ContainerError.notRunning(id)
        }

        logger.debug("Executing command in container", metadata: [
            "container": "\(name)",
            "command": "\(command.joined(separator: " "))"
        ])

        // Execute command in running container
        let execID = UUID().uuidString
        let process = try await container.exec(execID) { config in
            config.arguments = command
            config.environmentVariables = environment.map { "\($0.key)=\($0.value)" }
        }

        let exitStatus = try await process.wait()

        logger.debug("Command completed", metadata: [
            "container": "\(name)",
            "exitCode": "\(exitStatus.exitCode)"
        ])

        return exitStatus.exitCode
    }

    /// Stream logs from container
    /// Returns an AsyncStream that yields log lines from stdout and stderr
    public func logs(includeStderr: Bool = true) async -> AsyncStream<String> {
        // Merge stdout and stderr streams
        return AsyncStream { continuation in
            Task {
                await withTaskGroup(of: Void.self) { group in
                    // Stream stdout
                    group.addTask {
                        for await line in await self.stdoutBuffer.stream() {
                            continuation.yield(line)
                        }
                    }

                    // Stream stderr if requested
                    if includeStderr {
                        group.addTask {
                            for await line in await self.stderrBuffer.stream() {
                                continuation.yield(line)
                            }
                        }
                    }

                    await group.waitForAll()
                    continuation.finish()
                }
            }
        }
    }
}
