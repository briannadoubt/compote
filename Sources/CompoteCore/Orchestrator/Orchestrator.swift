import Foundation
import Containerization
import Logging

public enum OrchestratorError: Error, CustomStringConvertible {
    case serviceNotFound(String)
    case serviceNotRunning(String)
    case failedToStart(String, Error)
    case failedToStop(String, Error)

    public var description: String {
        switch self {
        case .serviceNotFound(let name):
            return "Service not found: \(name)"
        case .serviceNotRunning(let name):
            return "Service is known but not running: \(name). Start services with `compote up -d` or `compote start`."
        case .failedToStart(let name, let error):
            return "Failed to start service \(name): \(error)"
        case .failedToStop(let name, let error):
            return "Failed to stop service \(name): \(error)"
        }
    }
}

/// Main orchestrator for managing multi-service applications
public actor Orchestrator {
    public struct ServiceStatus: Sendable {
        public let name: String
        public let isRunning: Bool
        public let isKnown: Bool
    }

    private let composeFile: ComposeFile
    private let projectName: String
    private let logger: Logger

    private let imageManager: ImageManager
    private let volumeManager: VolumeManager
    private let networkManager: NetworkManager
    private let healthChecker: HealthChecker
    private let dependencyResolver: DependencyResolver
    private let serviceManager: ServiceManager
    private let kernelManager: KernelManager
    private let stateManager: StateManager
    private var containerManager: ContainerManager?

    private var containers: [String: ContainerRuntime] = [:]
    private var knownContainers: [String: StateManager.ContainerInfo] = [:]
    private var hasHydratedState = false

    public init(
        composeFile: ComposeFile,
        projectName: String,
        logger: Logger
    ) throws {
        self.composeFile = composeFile
        self.projectName = projectName
        self.logger = logger

        self.imageManager = try ImageManager(logger: logger)
        self.volumeManager = try VolumeManager(logger: logger)
        self.networkManager = NetworkManager(logger: logger)
        self.healthChecker = HealthChecker(logger: logger)
        self.dependencyResolver = DependencyResolver()
        self.serviceManager = ServiceManager(logger: logger)
        self.kernelManager = try KernelManager(logger: logger)
        self.stateManager = try StateManager(projectName: projectName, logger: logger)
    }

    /// Initialize the container manager
    private func initializeContainerManager() async throws -> ContainerManager {
        if let manager = containerManager {
            return manager
        }

        logger.info("Initializing container manager")

        // Get kernel
        let kernel = try await kernelManager.getKernel()
        let initfsReference = kernelManager.getInitfsReference()

        // Get network
        let network = try await networkManager.getVmnetNetwork()

        // Create container manager
        let manager = try await ContainerManager(
            kernel: kernel,
            initfsReference: initfsReference,
            network: network,
            rosetta: false
        )

        self.containerManager = manager
        logger.info("Container manager initialized")

        return manager
    }

    /// Start all services
    public func up(
        services: [String]? = nil,
        detach: Bool = false
    ) async throws {
        await hydrateStateIfNeeded()

        logger.info("Starting services", metadata: [
            "project": "\(projectName)"
        ])

        // Filter services if specified
        let servicesToStart = services ?? Array(composeFile.services.keys)

        // Create networks
        try await createNetworks()

        // Create volumes
        try await createVolumes()

        // Resolve startup order
        let filteredServices = composeFile.services.filter { servicesToStart.contains($0.key) }
        let startupOrder = try dependencyResolver.resolveStartupOrder(services: filteredServices)

        logger.info("Resolved startup order", metadata: [
            "batches": "\(startupOrder.count)"
        ])

        // Get health dependencies
        let healthDeps = dependencyResolver.getHealthDependencies(services: composeFile.services)

        // Start services in batches
        for (batchIndex, batch) in startupOrder.enumerated() {
            logger.info("Starting batch \(batchIndex + 1)/\(startupOrder.count)", metadata: [
                "services": "\(batch.joined(separator: ", "))"
            ])

            // Start all services in batch concurrently
            try await withThrowingTaskGroup(of: Void.self) { group in
                for serviceName in batch {
                    group.addTask {
                        try await self.startService(serviceName: serviceName)
                    }
                }

                try await group.waitForAll()
            }

            // Wait for health checks if required
            for serviceName in batch {
                if let service = composeFile.services[serviceName],
                   service.healthcheck != nil,
                   healthDeps[serviceName] != nil {
                    logger.info("Waiting for health check", metadata: [
                        "service": "\(serviceName)"
                    ])

                    if let container = containers[serviceName],
                       let healthCheck = service.healthcheck {
                        _ = try await healthChecker.runHealthCheck(
                            serviceName: serviceName,
                            healthCheck: healthCheck,
                            container: container
                        )
                    }
                }
            }
        }

        logger.info("All services started", metadata: [
            "project": "\(projectName)"
        ])

        // If not detached, wait for all containers
        if !detach {
            try await waitForContainers()
        }
    }

    /// Restart containers (stop then start)
    public func restart(
        services: [String]? = nil,
        timeout: Duration = .seconds(10)
    ) async throws {
        await hydrateStateIfNeeded()

        logger.info("Restarting services", metadata: [
            "project": "\(projectName)"
        ])

        // Stop services first
        try await stop(services: services, timeout: timeout)

        // Then start them again
        try await start(services: services)

        logger.info("Services restarted", metadata: [
            "project": "\(projectName)"
        ])
    }

    /// Start stopped containers
    public func start(services: [String]? = nil) async throws {
        await hydrateStateIfNeeded()

        logger.info("Starting services", metadata: [
            "project": "\(projectName)"
        ])

        // Determine which services to start
        let servicesToStart = services ?? Array(composeFile.services.keys)

        // Filter to only include services that exist but are not running
        var stoppedServices: [String] = []
        for serviceName in servicesToStart {
            if let container = containers[serviceName] {
                let isRunning = await container.getIsRunning()
                if !isRunning {
                    stoppedServices.append(serviceName)
                }
            }
        }

        guard !stoppedServices.isEmpty else {
            logger.info("No stopped containers to start")
            return
        }

        // Start services in dependency order
        let startupOrder = try dependencyResolver.resolveStartupOrder(services: composeFile.services)

        for batch in startupOrder {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for serviceName in batch where stoppedServices.contains(serviceName) {
                    group.addTask {
                        try await self.resumeService(serviceName: serviceName)
                    }
                }

                try await group.waitForAll()
            }
        }

        logger.info("Services started", metadata: [
            "project": "\(projectName)"
        ])
    }

    /// Stop containers without removing them
    public func stop(
        services: [String]? = nil,
        timeout: Duration = .seconds(10)
    ) async throws {
        await hydrateStateIfNeeded()

        logger.info("Stopping services", metadata: [
            "project": "\(projectName)"
        ])

        // Determine which services to stop
        let servicesToStop = services ?? Array(composeFile.services.keys)

        // Stop containers in reverse dependency order
        let startupOrder = try dependencyResolver.resolveStartupOrder(services: composeFile.services)

        for batch in startupOrder.reversed() {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for serviceName in batch where servicesToStop.contains(serviceName) {
                    group.addTask {
                        try await self.pauseService(serviceName: serviceName, timeout: timeout)
                    }
                }

                try await group.waitForAll()
            }
        }

        logger.info("Services stopped", metadata: [
            "project": "\(projectName)"
        ])
    }

    /// Stop all services and remove them
    public func down(removeVolumes: Bool = false) async throws {
        await hydrateStateIfNeeded()

        logger.info("Stopping services", metadata: [
            "project": "\(projectName)"
        ])

        // Stop containers in reverse order
        let startupOrder = try dependencyResolver.resolveStartupOrder(services: composeFile.services)

        for batch in startupOrder.reversed() {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for serviceName in batch {
                    group.addTask {
                        try await self.stopService(serviceName: serviceName)
                    }
                }

                try await group.waitForAll()
            }
        }

        // Remove networks
        try await removeNetworks()

        // Remove volumes if requested
        if removeVolumes {
            try await removeAllVolumes()
        }

        logger.info("All services stopped", metadata: [
            "project": "\(projectName)"
        ])
    }

    /// Start a specific service
    private func startService(serviceName: String) async throws {
        guard let service = composeFile.services[serviceName] else {
            throw OrchestratorError.serviceNotFound(serviceName)
        }

        logger.info("Starting service", metadata: ["service": "\(serviceName)"])

        do {
            // Initialize container manager if needed
            let manager = try await initializeContainerManager()

            // Build configuration
            let (imageReference, config) = try await serviceManager.buildConfiguration(
                serviceName: serviceName,
                service: service,
                projectName: projectName,
                imageManager: imageManager,
                volumeManager: volumeManager,
                networkManager: networkManager
            )

            // Create and start container
            let containerID = "\(projectName)_\(serviceName)_1"
            let container = ContainerRuntime(
                id: containerID,
                name: serviceName,
                containerManager: manager,
                logger: logger
            )

            // Start with default 2GB rootfs
            try await container.start(
                imageReference: imageReference,
                rootfsSizeInBytes: 2048 * 1024 * 1024,
                readOnly: false,
                configuration: config
            )
            containers[serviceName] = container

            // Save container to state
            try await stateManager.updateContainer(info: StateManager.ContainerInfo(
                id: containerID,
                name: serviceName,
                imageReference: imageReference
            ))
            knownContainers[serviceName] = StateManager.ContainerInfo(
                id: containerID,
                name: serviceName,
                imageReference: imageReference
            )

            logger.info("Service started", metadata: ["service": "\(serviceName)"])
        } catch {
            logger.error("Failed to start service", metadata: [
                "service": "\(serviceName)",
                "error": "\(error)"
            ])
            throw OrchestratorError.failedToStart(serviceName, error)
        }
    }

    /// Resume a stopped service
    private func resumeService(serviceName: String) async throws {
        guard composeFile.services[serviceName] != nil else {
            throw OrchestratorError.serviceNotFound(serviceName)
        }

        // Check if container exists but is stopped
        if let container = containers[serviceName] {
            let isRunning = await container.getIsRunning()
            if isRunning {
                logger.debug("Service already running", metadata: ["service": "\(serviceName)"])
                return
            }
        }

        // Container was stopped, need to recreate and start it
        // (VM containers typically can't be resumed after stop, need fresh start)
        logger.info("Starting service", metadata: ["service": "\(serviceName)"])

        do {
            // Remove old stopped container if it exists
            if containers[serviceName] != nil {
                containers.removeValue(forKey: serviceName)
            }

            // Start fresh (reuse startService logic)
            try await startService(serviceName: serviceName)
        } catch {
            logger.error("Failed to start service", metadata: [
                "service": "\(serviceName)",
                "error": "\(error)"
            ])
            throw OrchestratorError.failedToStart(serviceName, error)
        }
    }

    /// Pause a specific service (stop without removing)
    private func pauseService(serviceName: String, timeout: Duration) async throws {
        guard let container = containers[serviceName] else {
            logger.debug("Service not running", metadata: ["service": "\(serviceName)"])
            return
        }

        logger.info("Stopping service", metadata: ["service": "\(serviceName)"])

        do {
            try await container.stop(timeout: timeout)
            // Don't delete or remove from containers dictionary - keep for restart
            logger.info("Service stopped", metadata: ["service": "\(serviceName)"])
        } catch {
            logger.error("Failed to stop service", metadata: [
                "service": "\(serviceName)",
                "error": "\(error)"
            ])
            throw OrchestratorError.failedToStop(serviceName, error)
        }
    }

    /// Stop a specific service and remove it
    private func stopService(serviceName: String) async throws {
        guard let container = containers[serviceName] else {
            logger.debug("Service not running", metadata: ["service": "\(serviceName)"])
            return
        }

        logger.info("Stopping service", metadata: ["service": "\(serviceName)"])

        do {
            try await container.stop()
            try await container.delete()
            containers.removeValue(forKey: serviceName)

            // Remove from state
            try await stateManager.removeContainer(name: serviceName)
            knownContainers.removeValue(forKey: serviceName)

            logger.info("Service stopped", metadata: ["service": "\(serviceName)"])
        } catch {
            logger.error("Failed to stop service", metadata: [
                "service": "\(serviceName)",
                "error": "\(error)"
            ])
            throw OrchestratorError.failedToStop(serviceName, error)
        }
    }

    /// Create networks
    private func createNetworks() async throws {
        let networks = composeFile.networks ?? ["default": Network(driver: "bridge")]

        for (name, network) in networks {
            let networkName = "\(projectName)_\(name)"
            let driver = network.driver ?? "bridge"

            try await networkManager.createNetwork(
                name: networkName,
                driver: driver
            )

            // Save to state
            try await stateManager.updateNetwork(info: StateManager.NetworkInfo(
                name: networkName,
                driver: driver,
                subnet: "172.20.0.0/16",  // Default subnet
                gateway: "172.20.0.1"      // Default gateway
            ))
        }
    }

    /// Create volumes
    private func createVolumes() async throws {
        guard let volumes = composeFile.volumes else { return }

        for (name, volume) in volumes {
            let volumeName = "\(projectName)_\(name)"
            let isExternal = volume.external?.isExternal ?? false
            let driver = volume.driver ?? "local"

            let volumePath = try await volumeManager.createVolume(
                name: volumeName,
                driver: driver,
                isExternal: isExternal
            )

            // Save to state
            try await stateManager.updateVolume(info: StateManager.VolumeInfo(
                name: volumeName,
                driver: driver,
                mountPath: volumePath.path,
                isExternal: isExternal
            ))
        }
    }

    /// Remove networks
    private func removeNetworks() async throws {
        let networks = composeFile.networks ?? ["default": Network(driver: "bridge")]

        for name in networks.keys {
            let networkName = "\(projectName)_\(name)"
            try await networkManager.removeNetwork(name: networkName)
            try await stateManager.removeNetwork(name: networkName)
        }
    }

    /// Remove all volumes
    private func removeAllVolumes() async throws {
        // Load state to find all volumes created for this project
        let state = try await stateManager.load()

        // Remove volumes from compose file
        if let volumes = composeFile.volumes {
            for name in volumes.keys {
                let volumeName = "\(projectName)_\(name)"
                try await volumeManager.removeVolume(name: volumeName)
                try await stateManager.removeVolume(name: volumeName)
            }
        }

        // Also remove any volumes from state that might not be in current compose file
        if let state = state {
            for (name, _) in state.volumes {
                if name.hasPrefix("\(projectName)_") {
                    try await volumeManager.removeVolume(name: name)
                    try await stateManager.removeVolume(name: name)
                }
            }
        }

        logger.info("All volumes removed")
    }

    /// Wait for all containers to exit
    private func waitForContainers() async throws {
        try await withThrowingTaskGroup(of: (String, Int32).self) { group in
            for (name, container) in containers {
                group.addTask {
                    let exitCode = try await container.wait()
                    return (name, exitCode)
                }
            }

            for try await (name, exitCode) in group {
                logger.info("Container exited", metadata: [
                    "container": "\(name)",
                    "exitCode": "\(exitCode)"
                ])
            }
        }
    }

    /// List running services
    public func listServices() async -> [(String, Bool)] {
        let statuses = await listServiceStatuses()
        return statuses.map { ($0.name, $0.isRunning) }
    }

    /// List service statuses, including whether a service has been created before.
    public func listServiceStatuses() async -> [ServiceStatus] {
        await hydrateStateIfNeeded()

        var result: [ServiceStatus] = []
        let allServiceNames = Set(composeFile.services.keys).union(knownContainers.keys)
        for serviceName in allServiceNames.sorted() {
            let isRunning = await containers[serviceName]?.getIsRunning() ?? false
            let isKnown = knownContainers[serviceName] != nil || containers[serviceName] != nil
            result.append(ServiceStatus(name: serviceName, isRunning: isRunning, isKnown: isKnown))
        }
        return result
    }

    /// Stream logs from specified services
    /// - Parameters:
    ///   - services: List of service names to get logs from (all if empty)
    ///   - includeStderr: Whether to include stderr in the output
    /// - Returns: AsyncStream of log lines prefixed with service name
    public func streamLogs(
        services: [String] = [],
        includeStderr: Bool = true
    ) async -> AsyncStream<String> {
        await hydrateStateIfNeeded()

        let servicesToStream = services.isEmpty ? Array(composeFile.services.keys) : services

        return AsyncStream { continuation in
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for serviceName in servicesToStream {
                        guard let container = containers[serviceName] else {
                            continue
                        }

                        group.addTask {
                            let logStream = await container.logs(includeStderr: includeStderr)
                            for await line in logStream {
                                // Prefix each line with the service name
                                continuation.yield("[\(serviceName)] \(line)")
                            }
                        }
                    }

                    await group.waitForAll()
                    continuation.finish()
                }
            }
        }
    }

    /// Execute a command in a running container
    /// - Parameters:
    ///   - serviceName: Name of the service to execute the command in
    ///   - command: Command and arguments to execute
    ///   - environment: Environment variables for the command
    /// - Returns: Exit code from the command
    public func exec(
        serviceName: String,
        command: [String],
        environment: [String: String] = [:]
    ) async throws -> Int32 {
        await hydrateStateIfNeeded()

        guard let container = containers[serviceName] else {
            if knownContainers[serviceName] != nil {
                throw OrchestratorError.serviceNotRunning(serviceName)
            }
            throw OrchestratorError.serviceNotFound(serviceName)
        }

        guard await container.getIsRunning() else {
            throw OrchestratorError.serviceNotRunning(serviceName)
        }

        return try await container.exec(command: command, environment: environment)
    }

    /// Hydrate known container state from persisted state manager data.
    /// This keeps command behavior more consistent across separate CLI invocations.
    private func hydrateStateIfNeeded() async {
        guard !hasHydratedState else { return }
        hasHydratedState = true

        do {
            if let state = try await stateManager.load() {
                knownContainers = state.containers
            }
        } catch {
            logger.warning("Failed to hydrate state", metadata: ["error": "\(error)"])
        }
    }
}
