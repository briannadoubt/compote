import Foundation
import Containerization
import Logging
#if canImport(Darwin)
import Darwin
#endif

public enum OrchestratorError: Error, CustomStringConvertible {
    case serviceNotFound(String)
    case serviceNotRunning(String)
    case serviceReplicaNotFound(String, Int)
    case invalidServiceSelector(String)
    case invalidScale(String)
    case portForwardingFailed(String)
    case failedToStart(String, Error)
    case failedToStop(String, Error)

    public var description: String {
        switch self {
        case .serviceNotFound(let name):
            return "Service not found: \(name)"
        case .serviceNotRunning(let name):
            return "Service is known but not running: \(name). Start services with `compote up -d` or `compote start`."
        case .serviceReplicaNotFound(let service, let replica):
            return "Service replica not found: \(service)#\(replica). Create replicas with `compote scale \(service)=\(replica)`."
        case .invalidServiceSelector(let selector):
            return "Invalid service selector '\(selector)'. Use service or service#replica (for example: web or web#2)."
        case .invalidScale(let message):
            return "Invalid scale request: \(message)"
        case .portForwardingFailed(let message):
            return "Port forwarding failed: \(message)"
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
        public let runningReplicas: Int
        public let knownReplicas: Int
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

    private var containers: [String: [Int: ContainerRuntime]] = [:]
    private var knownContainers: [String: [Int: StateManager.ContainerInfo]] = [:]
    private var serviceIPs: [String: [Int: String]] = [:]
    private var portForwardPIDs: [String: Int32] = [:]
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

                    if let container = containers[serviceName]?[1],
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

        // Determine which services (or replicas) to start
        let parsedSelections = try services.map { selectors in
            try parseServiceSelections(selectors).values
        }
        let servicesToStart = parsedSelections?.keys.sorted() ?? Array(composeFile.services.keys)

        // Filter to only include services/replicas that are not running
        var stoppedServices: [String: ReplicaSelection] = [:]
        for serviceName in servicesToStart {
            let selection = parsedSelections?[serviceName] ?? .all
            let replicas = containers[serviceName] ?? [:]
            if case .indices(let selectedReplicas) = selection {
                var shouldStart = false
                for replicaIndex in selectedReplicas {
                    if let container = replicas[replicaIndex] {
                        if await container.getIsRunning() {
                            continue
                        }
                        shouldStart = true
                    } else if knownContainers[serviceName]?[replicaIndex] != nil {
                        shouldStart = true
                    } else {
                        throw OrchestratorError.serviceReplicaNotFound(serviceName, replicaIndex)
                    }
                }
                if shouldStart {
                    stoppedServices[serviceName] = selection
                }
            } else if !replicas.isEmpty {
                let hasRunningReplica = await hasRunningReplicas(serviceName: serviceName)
                if !hasRunningReplica {
                    stoppedServices[serviceName] = selection
                }
            } else if knownContainers[serviceName] != nil {
                // Service is known from persisted state but not currently running in this process.
                stoppedServices[serviceName] = selection
            }
        }

        guard !stoppedServices.isEmpty else {
            logger.info("No stopped containers to start")
            return
        }

        // Start services in dependency order
        let startupOrder = try dependencyResolver.resolveStartupOrder(services: composeFile.services)

        for batch in startupOrder {
            for serviceName in batch where stoppedServices[serviceName] != nil {
                let replicaSelection = stoppedServices[serviceName] ?? .all
                try await resumeService(
                    serviceName: serviceName,
                    replicaIndices: replicaIndices(for: replicaSelection)
                )
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

        // Determine which services (or replicas) to stop
        let parsedSelections = try services.map { selectors in
            try parseServiceSelections(selectors).values
        }
        let servicesToStop: Set<String>
        if let parsedSelections {
            servicesToStop = Set(parsedSelections.keys)
        } else {
            servicesToStop = Set(composeFile.services.keys)
        }

        // Stop containers in reverse dependency order
        let startupOrder = try dependencyResolver.resolveStartupOrder(services: composeFile.services)

        for batch in startupOrder.reversed() {
            for serviceName in batch where servicesToStop.contains(serviceName) {
                let replicaSelection = parsedSelections?[serviceName] ?? .all
                try await pauseService(
                    serviceName: serviceName,
                    timeout: timeout,
                    replicaIndices: replicaIndices(for: replicaSelection)
                )
            }
        }

        logger.info("Services stopped", metadata: [
            "project": "\(projectName)"
        ])
    }

    /// Pull images for selected services
    public func pull(services: [String]? = nil) async throws {
        await hydrateStateIfNeeded()

        let servicesToPull = services ?? Array(composeFile.services.keys)

        logger.info("Pulling service images", metadata: [
            "project": "\(projectName)",
            "count": "\(servicesToPull.count)"
        ])

        for serviceName in servicesToPull {
            guard let service = composeFile.services[serviceName] else {
                throw OrchestratorError.serviceNotFound(serviceName)
            }

            guard let image = service.image else {
                logger.info("Skipping service without image reference", metadata: [
                    "service": "\(serviceName)"
                ])
                continue
            }

            _ = try await imageManager.pullImage(reference: image)

            logger.info("Image pulled", metadata: [
                "service": "\(serviceName)",
                "image": "\(image)"
            ])
        }
    }

    /// Push images for selected services
    public func push(services: [String]? = nil) async throws {
        await hydrateStateIfNeeded()

        let servicesToPush = services ?? Array(composeFile.services.keys)

        logger.info("Pushing service images", metadata: [
            "project": "\(projectName)",
            "count": "\(servicesToPush.count)"
        ])

        for serviceName in servicesToPush {
            guard let service = composeFile.services[serviceName] else {
                throw OrchestratorError.serviceNotFound(serviceName)
            }

            let imageToPush: String?
            if let image = service.image {
                imageToPush = image
            } else if service.build != nil {
                imageToPush = "\(projectName)_\(serviceName):latest"
            } else {
                imageToPush = nil
            }

            guard let imageReference = imageToPush else {
                logger.info("Skipping service without pushable image", metadata: [
                    "service": "\(serviceName)"
                ])
                continue
            }

            try await imageManager.pushImage(reference: imageReference)

            logger.info("Image pushed", metadata: [
                "service": "\(serviceName)",
                "image": "\(imageReference)"
            ])
        }
    }

    /// Scale a service to the requested replica count.
    public func scale(serviceName: String, replicas: Int) async throws {
        await hydrateStateIfNeeded()

        guard replicas >= 0 else {
            throw OrchestratorError.invalidScale("replica count must be >= 0")
        }
        guard composeFile.services[serviceName] != nil else {
            throw OrchestratorError.serviceNotFound(serviceName)
        }

        try await createNetworks()
        try await createVolumes()

        let currentReplicas = knownReplicaIndices(for: serviceName)
        let currentMax = currentReplicas.max() ?? 0

        logger.info("Scaling service", metadata: [
            "service": "\(serviceName)",
            "from": "\(currentReplicas.count)",
            "to": "\(replicas)"
        ])

        if replicas > currentReplicas.count {
            // Ensure replica 1 always exists first for stable behavior.
            for replicaIndex in 1...replicas where !currentReplicas.contains(replicaIndex) {
                try await startService(serviceName: serviceName, replicaIndex: replicaIndex)
            }
        } else if replicas < currentReplicas.count {
            // Remove highest-numbered replicas first.
            for replicaIndex in stride(from: currentMax, through: 1, by: -1) {
                guard replicaIndex > replicas else { continue }
                try await removeReplica(serviceName: serviceName, replicaIndex: replicaIndex)
            }
        }
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

        // Ensure persisted container state is cleaned up even if containers were
        // not attachable in this process (e.g. fresh CLI invocation).
        let allServiceNames = Array(composeFile.services.keys)
        try await removeKnownContainerState(for: allServiceNames)
        try await removeAllPortForwards()

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
    private func startService(serviceName: String, replicaIndex: Int = 1) async throws {
        guard let service = composeFile.services[serviceName] else {
            throw OrchestratorError.serviceNotFound(serviceName)
        }

        let displayName = containerDisplayName(serviceName: serviceName, replicaIndex: replicaIndex)
        logger.info("Starting service", metadata: [
            "service": "\(serviceName)",
            "replica": "\(replicaIndex)"
        ])

        do {
            // Initialize container manager if needed
            let manager = try await initializeContainerManager()
            let containerID = containerID(serviceName: serviceName, replicaIndex: replicaIndex)

            // Best-effort network attachment metadata for service discovery.
            // If default network is unavailable, we continue without DNS mapping.
            let defaultNetworkName = "\(projectName)_default"
            if let ipAddress = try? await networkManager.connectContainer(
                containerID: containerID,
                networkName: defaultNetworkName
            ) {
                var replicas = serviceIPs[serviceName] ?? [:]
                replicas[replicaIndex] = ipAddress
                serviceIPs[serviceName] = replicas
            }

            let hostsEntries = makeServiceDiscoveryHostsEntries()

            // Build configuration
            let (imageReference, config) = try await serviceManager.buildConfiguration(
                serviceName: serviceName,
                service: service,
                composeFile: composeFile,
                projectName: projectName,
                hostsEntries: hostsEntries,
                imageManager: imageManager,
                volumeManager: volumeManager,
                networkManager: networkManager
            )

            // Create and start container
            let container = ContainerRuntime(
                id: containerID,
                name: displayName,
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
            var replicas = containers[serviceName] ?? [:]
            replicas[replicaIndex] = container
            containers[serviceName] = replicas

            if let targetIP = serviceIPs[serviceName]?[replicaIndex] {
                try await setupPortForwards(
                    serviceName: serviceName,
                    replicaIndex: replicaIndex,
                    service: service,
                    targetIP: targetIP
                )
            }

            // Save container to state
            try await stateManager.updateContainer(info: StateManager.ContainerInfo(
                id: containerID,
                name: displayName,
                imageReference: imageReference,
                serviceName: serviceName,
                replicaIndex: replicaIndex
            ))
            var knownReplicas = knownContainers[serviceName] ?? [:]
            knownReplicas[replicaIndex] = StateManager.ContainerInfo(
                id: containerID,
                name: displayName,
                imageReference: imageReference,
                serviceName: serviceName,
                replicaIndex: replicaIndex
            )
            knownContainers[serviceName] = knownReplicas

            logger.info("Service started", metadata: [
                "service": "\(serviceName)",
                "replica": "\(replicaIndex)"
            ])
        } catch {
            logger.error("Failed to start service", metadata: [
                "service": "\(serviceName)",
                "error": "\(error)"
            ])
            throw OrchestratorError.failedToStart(serviceName, error)
        }
    }

    /// Resume a stopped service
    private func resumeService(
        serviceName: String,
        replicaIndices: Set<Int>? = nil
    ) async throws {
        guard composeFile.services[serviceName] != nil else {
            throw OrchestratorError.serviceNotFound(serviceName)
        }

        if replicaIndices == nil {
            let hasRunning = await hasRunningReplicas(serviceName: serviceName)
            if hasRunning {
                logger.debug("Service already running", metadata: ["service": "\(serviceName)"])
                return
            }
        }

        logger.info("Starting service", metadata: ["service": "\(serviceName)"])

        do {
            // Remove old stopped runtime containers if they exist
            if let existing = containers[serviceName], !existing.isEmpty {
                containers.removeValue(forKey: serviceName)
            }

            let knownIndices = Set(knownReplicaIndices(for: serviceName))
            let replicasToStart: [Int]
            if let replicaIndices {
                replicasToStart = replicaIndices.sorted()
            } else {
                let defaults = knownIndices.sorted()
                replicasToStart = defaults.isEmpty ? [1] : defaults
            }

            for replicaIndex in replicasToStart {
                if !knownIndices.contains(replicaIndex) && containers[serviceName]?[replicaIndex] == nil {
                    throw OrchestratorError.serviceReplicaNotFound(serviceName, replicaIndex)
                }

                if let existing = containers[serviceName]?[replicaIndex],
                   await existing.getIsRunning() {
                    continue
                }
                try await startService(serviceName: serviceName, replicaIndex: replicaIndex)
            }
        } catch {
            logger.error("Failed to start service", metadata: [
                "service": "\(serviceName)",
                "error": "\(error)"
            ])
            throw OrchestratorError.failedToStart(serviceName, error)
        }
    }

    /// Pause a specific service (stop without removing)
    private func pauseService(
        serviceName: String,
        timeout: Duration,
        replicaIndices: Set<Int>? = nil
    ) async throws {
        guard let replicas = containers[serviceName], !replicas.isEmpty else {
            logger.debug("Service not running", metadata: ["service": "\(serviceName)"])
            return
        }

        logger.info("Stopping service", metadata: ["service": "\(serviceName)"])

        do {
            let replicaOrder: [Int]
            if let replicaIndices {
                replicaOrder = replicaIndices.sorted()
            } else {
                replicaOrder = Array(replicas.keys).sorted()
            }

            for replicaIndex in replicaOrder {
                guard let container = replicas[replicaIndex] else {
                    throw OrchestratorError.serviceReplicaNotFound(serviceName, replicaIndex)
                }
                guard await container.getIsRunning() else {
                    continue
                }
                try await container.stop(timeout: timeout)
                try await removePortForwards(serviceName: serviceName, replicaIndex: replicaIndex)
            }
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
        guard let replicas = containers[serviceName], !replicas.isEmpty else {
            logger.debug("Service not running", metadata: ["service": "\(serviceName)"])
            return
        }

        logger.info("Stopping service", metadata: ["service": "\(serviceName)"])

        do {
            for (replicaIndex, container) in replicas {
                try await container.stop()
                try await container.delete()
                try await removePortForwards(serviceName: serviceName, replicaIndex: replicaIndex)
            }
            containers.removeValue(forKey: serviceName)

            // Remove from state
            if let knownReplicas = knownContainers[serviceName] {
                for (_, info) in knownReplicas {
                    try await stateManager.removeContainer(name: info.name)
                }
            }
            knownContainers.removeValue(forKey: serviceName)
            serviceIPs.removeValue(forKey: serviceName)

            logger.info("Service stopped", metadata: ["service": "\(serviceName)"])
        } catch {
            logger.error("Failed to stop service", metadata: [
                "service": "\(serviceName)",
                "error": "\(error)"
            ])
            throw OrchestratorError.failedToStop(serviceName, error)
        }
    }

    private func removeReplica(serviceName: String, replicaIndex: Int) async throws {
        guard let container = containers[serviceName]?[replicaIndex] else {
            return
        }

        do {
            try await container.stop()
            try await container.delete()
            try await removePortForwards(serviceName: serviceName, replicaIndex: replicaIndex)

            var runtimeReplicas = containers[serviceName] ?? [:]
            runtimeReplicas.removeValue(forKey: replicaIndex)
            containers[serviceName] = runtimeReplicas.isEmpty ? nil : runtimeReplicas

            if let info = knownContainers[serviceName]?[replicaIndex] {
                try await stateManager.removeContainer(name: info.name)
            }

            var knownReplicas = knownContainers[serviceName] ?? [:]
            knownReplicas.removeValue(forKey: replicaIndex)
            knownContainers[serviceName] = knownReplicas.isEmpty ? nil : knownReplicas

            var ips = serviceIPs[serviceName] ?? [:]
            ips.removeValue(forKey: replicaIndex)
            serviceIPs[serviceName] = ips.isEmpty ? nil : ips
        } catch {
            throw OrchestratorError.failedToStop("\(serviceName)#\(replicaIndex)", error)
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

    /// Remove known container state entries for services.
    private func removeKnownContainerState(for services: [String]) async throws {
        for serviceName in services {
            if let knownReplicas = knownContainers[serviceName] {
                knownContainers.removeValue(forKey: serviceName)
                serviceIPs.removeValue(forKey: serviceName)
                for (_, info) in knownReplicas {
                    try await stateManager.removeContainer(name: info.name)
                }
            }
        }
    }

    /// Wait for all containers to exit
    private func waitForContainers() async throws {
        try await withThrowingTaskGroup(of: (String, Int32).self) { group in
            for (_, replicas) in containers {
                for (_, container) in replicas {
                    let name = container.name
                    group.addTask {
                        let exitCode = try await container.wait()
                        return (name, exitCode)
                    }
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
            let runningReplicas = await runningReplicaCount(serviceName: serviceName)
            let isRunning = runningReplicas > 0
            let knownReplicas = knownReplicaIndices(for: serviceName).count
            let isKnown = knownContainers[serviceName] != nil || containers[serviceName] != nil
            result.append(
                ServiceStatus(
                    name: serviceName,
                    isRunning: isRunning,
                    isKnown: isKnown,
                    runningReplicas: runningReplicas,
                    knownReplicas: knownReplicas
                )
            )
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
        includeStderr: Bool = true,
        tail: Int? = nil,
        follow: Bool = true
    ) async throws -> AsyncStream<String> {
        await hydrateStateIfNeeded()

        let selectors = try resolveServiceSelectors(services)

        return AsyncStream { continuation in
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for selector in selectors {
                        let serviceName = selector.serviceName
                        guard let replicas = containers[serviceName], !replicas.isEmpty else {
                            continue
                        }

                        let replicasToStream: [(Int, ContainerRuntime)]
                        if let replicaIndex = selector.replicaIndex {
                            if let container = replicas[replicaIndex] {
                                replicasToStream = [(replicaIndex, container)]
                            } else {
                                continue
                            }
                        } else {
                            replicasToStream = replicas.sorted { $0.key < $1.key }
                        }

                        for (replicaIndex, container) in replicasToStream {
                            group.addTask {
                                let logStream = await container.logs(
                                    includeStderr: includeStderr,
                                    tail: tail,
                                    follow: follow
                                )
                                let label = replicaIndex == 1 ? serviceName : "\(serviceName)#\(replicaIndex)"
                                for await line in logStream {
                                    continuation.yield("[\(label)] \(line)")
                                }
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
        replicaIndex: Int? = nil,
        command: [String],
        environment: [String: String] = [:]
    ) async throws -> Int32 {
        await hydrateStateIfNeeded()

        let selectedReplicaIndex: Int
        if let replicaIndex {
            selectedReplicaIndex = replicaIndex
        } else {
            let runningReplicas = await runningReplicaIndices(serviceName: serviceName)
            if let firstRunning = runningReplicas.first {
                selectedReplicaIndex = firstRunning
            } else if knownContainers[serviceName] != nil {
                throw OrchestratorError.serviceNotRunning(serviceName)
            } else {
                throw OrchestratorError.serviceNotFound(serviceName)
            }
        }

        guard let container = containers[serviceName]?[selectedReplicaIndex] else {
            if knownContainers[serviceName] != nil {
                let selector = selectedReplicaIndex == 1 ? serviceName : "\(serviceName)#\(selectedReplicaIndex)"
                throw OrchestratorError.serviceNotRunning(selector)
            }
            throw OrchestratorError.serviceNotFound(serviceName)
        }

        guard await container.getIsRunning() else {
            let selector = selectedReplicaIndex == 1 ? serviceName : "\(serviceName)#\(selectedReplicaIndex)"
            throw OrchestratorError.serviceNotRunning(selector)
        }

        return try await container.exec(command: command, environment: environment)
    }

    private func parseServiceSelections(_ values: [String]) throws -> ServiceSelections {
        do {
            return try ServiceSelections.parse(values, validServices: Set(composeFile.services.keys))
        } catch let error as ServiceSelectionError {
            switch error {
            case .invalidSelector(let value):
                throw OrchestratorError.invalidServiceSelector(value)
            case .unknownService(let service):
                throw OrchestratorError.serviceNotFound(service)
            }
        } catch {
            throw error
        }
    }

    private func replicaIndices(for selection: ReplicaSelection) -> Set<Int>? {
        switch selection {
        case .all:
            return nil
        case .indices(let indices):
            return indices
        }
    }

    private func resolveServiceSelectors(_ selectors: [String]) throws -> [ServiceSelector] {
        if selectors.isEmpty {
            return composeFile.services.keys.sorted().map { ServiceSelector(serviceName: $0, replicaIndex: nil) }
        }

        do {
            return try selectors.map(ServiceSelector.parse)
        } catch let error as ServiceSelectionError {
            switch error {
            case .invalidSelector(let value):
                throw OrchestratorError.invalidServiceSelector(value)
            case .unknownService(let service):
                throw OrchestratorError.serviceNotFound(service)
            }
        } catch {
            throw error
        }
    }

    private func containerDisplayName(serviceName: String, replicaIndex: Int) -> String {
        replicaIndex == 1 ? serviceName : "\(serviceName)-\(replicaIndex)"
    }

    private func containerID(serviceName: String, replicaIndex: Int) -> String {
        "\(projectName)_\(serviceName)_\(replicaIndex)"
    }

    private func knownReplicaIndices(for serviceName: String) -> [Int] {
        let runtimeReplicas = containers[serviceName].map { Array($0.keys) } ?? []
        let knownReplicas = knownContainers[serviceName].map { Array($0.keys) } ?? []
        return Array(Set(runtimeReplicas).union(knownReplicas)).sorted()
    }

    private func makeServiceDiscoveryHostsEntries() -> [Hosts.Entry] {
        var entries: [Hosts.Entry] = []

        for (serviceName, replicas) in serviceIPs {
            for (replicaIndex, ipAddress) in replicas {
                let hostname = replicaIndex == 1 ? serviceName : "\(serviceName)-\(replicaIndex)"
                entries.append(Hosts.Entry(ipAddress: ipAddress, hostnames: [hostname]))
            }
        }

        return entries.sorted { lhs, rhs in
            lhs.hostnames.joined(separator: ",") < rhs.hostnames.joined(separator: ",")
        }
    }

    private func ensureSocatAvailable() throws {
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        check.arguments = ["which", "socat"]
        check.standardOutput = Pipe()
        check.standardError = Pipe()

        do {
            try check.run()
            check.waitUntilExit()
            guard check.terminationStatus == 0 else {
                throw OrchestratorError.portForwardingFailed(
                    "Port mappings require `socat` to be installed and on PATH."
                )
            }
        } catch {
            throw OrchestratorError.portForwardingFailed("Failed to check for socat: \(error)")
        }
    }

    private func portForwardID(serviceName: String, replicaIndex: Int, hostPort: Int, proto: String) -> String {
        "\(serviceName)#\(replicaIndex)#\(proto)#\(hostPort)"
    }

    private func setupPortForwards(
        serviceName: String,
        replicaIndex: Int,
        service: Service,
        targetIP: String
    ) async throws {
        guard let ports = service.ports, !ports.isEmpty else { return }

        try ensureSocatAvailable()
        try await removePortForwards(serviceName: serviceName, replicaIndex: replicaIndex)

        for portSpec in ports {
            let mapping: PortMapping
            do {
                mapping = try PortMappingParser.parse(portSpec)
            } catch let parseError as PortMappingParseError {
                throw OrchestratorError.portForwardingFailed(parseError.description)
            } catch {
                throw OrchestratorError.portForwardingFailed("Invalid port mapping '\(portSpec)': \(error)")
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            let sourceAddress: String
            let targetAddress: String
            if mapping.proto == "udp" {
                sourceAddress = "UDP4-RECVFROM:\(mapping.hostPort),bind=\(mapping.hostIP),reuseaddr,fork"
                targetAddress = "UDP4-SENDTO:\(targetIP):\(mapping.containerPort)"
            } else {
                sourceAddress = "TCP-LISTEN:\(mapping.hostPort),bind=\(mapping.hostIP),reuseaddr,fork"
                targetAddress = "TCP:\(targetIP):\(mapping.containerPort)"
            }
            process.arguments = ["socat", sourceAddress, targetAddress]

            let nullDevice = FileHandle.nullDevice
            process.standardInput = nullDevice
            process.standardOutput = nullDevice
            process.standardError = nullDevice

            do {
                try process.run()
                let pid = process.processIdentifier
                let id = portForwardID(
                    serviceName: serviceName,
                    replicaIndex: replicaIndex,
                    hostPort: mapping.hostPort,
                    proto: mapping.proto
                )
                portForwardPIDs[id] = pid
                try await stateManager.updatePortForward(info: StateManager.PortForwardInfo(
                    id: id,
                    serviceName: serviceName,
                    replicaIndex: replicaIndex,
                    hostIP: mapping.hostIP,
                    hostPort: mapping.hostPort,
                    targetIP: targetIP,
                    targetPort: mapping.containerPort,
                    pid: pid
                ))
            } catch {
                throw OrchestratorError.portForwardingFailed(
                    "Could not create forward \(portSpec) for \(serviceName): \(error)"
                )
            }
        }
    }

    private func removePortForwards(serviceName: String, replicaIndex: Int) async throws {
        let state = try await stateManager.load()
        guard let state else { return }

        let forwards = state.portForwards.values.filter {
            $0.serviceName == serviceName && $0.replicaIndex == replicaIndex
        }

        for forward in forwards {
            terminatePortForward(pid: forward.pid)
            portForwardPIDs.removeValue(forKey: forward.id)
            try await stateManager.removePortForward(id: forward.id)
        }
    }

    private func removeAllPortForwards() async throws {
        let state = try await stateManager.load()
        guard let state else { return }

        for forward in state.portForwards.values {
            terminatePortForward(pid: forward.pid)
            portForwardPIDs.removeValue(forKey: forward.id)
            try await stateManager.removePortForward(id: forward.id)
        }
    }

    private func terminatePortForward(pid: Int32) {
        #if canImport(Darwin)
        _ = kill(pid, SIGTERM)
        #endif
    }

    /// Hydrate known container state from persisted state manager data.
    /// This keeps command behavior more consistent across separate CLI invocations.
    private func hydrateStateIfNeeded() async {
        guard !hasHydratedState else { return }
        hasHydratedState = true

        do {
            if let state = try await stateManager.load() {
                var hydrated: [String: [Int: StateManager.ContainerInfo]] = [:]
                for (_, info) in state.containers {
                    let service = info.serviceName ?? info.name
                    let replica = info.replicaIndex ?? 1
                    var replicas = hydrated[service] ?? [:]
                    replicas[replica] = info
                    hydrated[service] = replicas
                }
                knownContainers = hydrated
                portForwardPIDs = Dictionary(uniqueKeysWithValues: state.portForwards.map { ($0.key, $0.value.pid) })
            }
        } catch {
            logger.warning("Failed to hydrate state", metadata: ["error": "\(error)"])
        }
    }

    private func hasRunningReplicas(serviceName: String) async -> Bool {
        await runningReplicaCount(serviceName: serviceName) > 0
    }

    private func runningReplicaCount(serviceName: String) async -> Int {
        guard let replicas = containers[serviceName], !replicas.isEmpty else {
            return 0
        }
        var runningCount = 0
        for (_, container) in replicas {
            if await container.getIsRunning() {
                runningCount += 1
            }
        }
        return runningCount
    }

    private func runningReplicaIndices(serviceName: String) async -> [Int] {
        guard let replicas = containers[serviceName], !replicas.isEmpty else {
            return []
        }
        var result: [Int] = []
        for (replicaIndex, container) in replicas {
            if await container.getIsRunning() {
                result.append(replicaIndex)
            }
        }
        return result.sorted()
    }
}
