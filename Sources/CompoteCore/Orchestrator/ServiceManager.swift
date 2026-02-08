import Foundation
import Containerization
import Logging

/// Manages individual service lifecycle
public struct ServiceManager: Sendable {
    private let logger: Logger

    public init(logger: Logger) {
        self.logger = logger
    }

    /// Build container configuration and image reference from service definition
    public func buildConfiguration(
        serviceName: String,
        service: Service,
        composeFile: ComposeFile,
        projectName: String,
        imageManager: ImageManager,
        volumeManager: VolumeManager,
        networkManager: NetworkManager
    ) async throws -> (imageReference: String, config: LinuxContainer.Configuration) {
        var config = LinuxContainer.Configuration()

        // Resolve image reference
        let imageReference: String
        if let image = service.image {
            // Ensure image is pulled/available
            _ = try await imageManager.pullImage(reference: image)
            imageReference = image
        } else if let build = service.build {
            let context = build.context ?? "."
            let dockerfile = build.dockerfile ?? "Dockerfile"
            let tag = "\(projectName)_\(serviceName):latest"
            let buildArgs = build.args ?? [:]
            _ = try await imageManager.buildImage(
                context: context,
                dockerfile: dockerfile,
                tag: tag,
                buildArgs: buildArgs
            )
            imageReference = tag
        } else {
            throw ServiceError.noImageOrBuild(serviceName)
        }

        // Set hostname
        if let hostname = service.hostname {
            config.hostname = hostname
        } else {
            config.hostname = serviceName
        }

        // Set command
        if let command = service.command {
            config.process.arguments = command.asArray
        }

        // Set working directory
        if let workingDir = service.working_dir {
            config.process.workingDirectory = workingDir
        }

        // Set environment variables
        if let env = service.environment {
            let envDict = env.asDictionary
            config.process.environmentVariables = envDict.map { "\($0.key)=\($0.value)" }
        }

        // Set resource limits
        if let deploy = service.deploy {
            if let resources = deploy.resources {
                if let limits = resources.limits {
                    if let cpuString = limits.cpus, let cpus = Double(cpuString) {
                        config.cpus = Int(cpus)
                    }
                    if let memString = limits.memory {
                        config.memoryInBytes = parseMemory(memString)
                    }
                }
            }
        }

        // Process volume mounts
        if let volumes = service.volumes {
            for volumeSpec in volumes {
                let mount = try await processVolumeMount(
                    volumeSpec: volumeSpec,
                    serviceName: serviceName,
                    projectName: projectName,
                    volumeManager: volumeManager
                )
                config.mounts.append(mount)
            }
        }

        // Mount service configs as read-only files
        if let configRefs = service.configs {
            for configRef in configRefs {
                let mount = try processConfigMount(
                    reference: configRef,
                    composeFile: composeFile
                )
                config.mounts.append(mount)
            }
        }

        // Mount service secrets as read-only files
        if let secretRefs = service.secrets {
            for secretRef in secretRefs {
                let mount = try processSecretMount(
                    reference: secretRef,
                    composeFile: composeFile
                )
                config.mounts.append(mount)
            }
        }

        logger.debug("Built configuration for service", metadata: [
            "service": "\(serviceName)",
            "image": "\(imageReference)",
            "mounts": "\(config.mounts.count)"
        ])

        return (imageReference, config)
    }

    private func processConfigMount(
        reference: ServiceConfigReference,
        composeFile: ComposeFile
    ) throws -> Mount {
        let source = reference.source

        guard let config = composeFile.configs?[source] else {
            throw ServiceError.configNotFound(source)
        }

        if config.external == true {
            throw ServiceError.externalConfigNotSupported(source)
        }

        guard let filePath = config.file else {
            throw ServiceError.configFileMissing(source)
        }

        let hostPath = resolveHostPath(filePath)
        let targetPath = reference.target ?? "/\(source)"

        return Mount.share(
            source: hostPath.path,
            destination: targetPath,
            runtimeOptions: ["ro"]
        )
    }

    private func processSecretMount(
        reference: ServiceSecretReference,
        composeFile: ComposeFile
    ) throws -> Mount {
        let source = reference.source

        guard let secret = composeFile.secrets?[source] else {
            throw ServiceError.secretNotFound(source)
        }

        if secret.external == true {
            throw ServiceError.externalSecretNotSupported(source)
        }

        guard let filePath = secret.file else {
            throw ServiceError.secretFileMissing(source)
        }

        let hostPath = resolveHostPath(filePath)
        let targetPath = reference.target ?? "/run/secrets/\(source)"

        return Mount.share(
            source: hostPath.path,
            destination: targetPath,
            runtimeOptions: ["ro"]
        )
    }

    private func resolveHostPath(_ path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        if path.hasPrefix("~") {
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        }
        let cwd = FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: cwd).appendingPathComponent(path)
    }

    /// Parse memory string (e.g., "512m", "1g") to bytes
    private func parseMemory(_ memory: String) -> UInt64 {
        let value = memory.dropLast()
        let unit = memory.last

        guard let number = UInt64(value) else { return 1024 * 1024 * 1024 } // Default 1GB

        switch unit {
        case "k", "K":
            return number * 1024
        case "m", "M":
            return number * 1024 * 1024
        case "g", "G":
            return number * 1024 * 1024 * 1024
        default:
            return number
        }
    }

    /// Process a volume mount specification and return a Mount object
    private func processVolumeMount(
        volumeSpec: String,
        serviceName: String,
        projectName: String,
        volumeManager: VolumeManager
    ) async throws -> Mount {
        // Parse volume specification
        let (source, target, readOnly) = await volumeManager.parseVolumeMount(volumeSpec)

        // Check if it's a named volume or bind mount
        if source.hasPrefix("/") || source.hasPrefix(".") || source.hasPrefix("~") {
            // Bind mount - source is a path
            let hostPath: URL
            if source.hasPrefix("/") {
                hostPath = URL(fileURLWithPath: source)
            } else if source.hasPrefix("~") {
                let expandedPath = NSString(string: source).expandingTildeInPath
                hostPath = URL(fileURLWithPath: expandedPath)
            } else {
                // Relative path - resolve relative to current directory
                let cwd = FileManager.default.currentDirectoryPath
                hostPath = URL(fileURLWithPath: cwd).appendingPathComponent(source)
            }

            // Create bind mount
            let options = readOnly ? ["ro"] : []
            return Mount.share(
                source: hostPath.path,
                destination: target,
                runtimeOptions: options
            )
        } else {
            // Named volume
            let volumeName = "\(projectName)_\(source)"
            let volumePath = try await volumeManager.getVolumePath(name: volumeName)

            // Create volume mount
            let options = readOnly ? ["ro"] : []
            return Mount.share(
                source: volumePath.path,
                destination: target,
                runtimeOptions: options
            )
        }
    }
}

public enum ServiceError: Error, CustomStringConvertible {
    case noImageOrBuild(String)
    case configNotFound(String)
    case secretNotFound(String)
    case configFileMissing(String)
    case secretFileMissing(String)
    case externalConfigNotSupported(String)
    case externalSecretNotSupported(String)

    public var description: String {
        switch self {
        case .noImageOrBuild(let service):
            return "Service \(service) has neither image nor build configuration"
        case .configNotFound(let name):
            return "Config not found: \(name)"
        case .secretNotFound(let name):
            return "Secret not found: \(name)"
        case .configFileMissing(let name):
            return "Config \(name) does not define a file path"
        case .secretFileMissing(let name):
            return "Secret \(name) does not define a file path"
        case .externalConfigNotSupported(let name):
            return "External config \(name) is not supported yet"
        case .externalSecretNotSupported(let name):
            return "External secret \(name) is not supported yet"
        }
    }
}
