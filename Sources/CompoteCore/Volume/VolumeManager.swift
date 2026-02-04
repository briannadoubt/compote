import Foundation
import ContainerizationEXT4
import Logging

public enum VolumeError: Error, CustomStringConvertible {
    case failedToCreate(String)
    case notFound(String)
    case invalidPath(String)

    public var description: String {
        switch self {
        case .failedToCreate(let msg):
            return "Failed to create volume: \(msg)"
        case .notFound(let name):
            return "Volume not found: \(name)"
        case .invalidPath(let path):
            return "Invalid volume path: \(path)"
        }
    }
}

/// Manages named volumes and bind mounts
public actor VolumeManager {
    private var volumes: [String: VolumeInfo] = [:]
    private let volumesDir: URL
    private let logger: Logger

    public struct VolumeInfo: Sendable {
        public let name: String
        public let driver: String
        public let mountPath: URL
        public let isExternal: Bool
    }

    public init(logger: Logger) throws {
        self.logger = logger

        // Store volumes in ~/Library/Application Support/compote/volumes
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        self.volumesDir = appSupport
            .appendingPathComponent("compote")
            .appendingPathComponent("volumes")

        // Create volumes directory
        try FileManager.default.createDirectory(
            at: volumesDir,
            withIntermediateDirectories: true
        )
    }

    /// Create a named volume
    public func createVolume(
        name: String,
        driver: String = "local",
        isExternal: Bool = false
    ) async throws -> URL {
        if let existing = volumes[name] {
            logger.debug("Volume already exists", metadata: ["volume": "\(name)"])
            return existing.mountPath
        }

        logger.info("Creating volume", metadata: [
            "volume": "\(name)",
            "driver": "\(driver)"
        ])

        let volumePath = volumesDir.appendingPathComponent(name)

        do {
            // Create volume directory
            try FileManager.default.createDirectory(
                at: volumePath,
                withIntermediateDirectories: true
            )

            let info = VolumeInfo(
                name: name,
                driver: driver,
                mountPath: volumePath,
                isExternal: isExternal
            )
            volumes[name] = info

            logger.info("Volume created", metadata: [
                "volume": "\(name)",
                "path": "\(volumePath.path)"
            ])

            return volumePath
        } catch {
            logger.error("Failed to create volume", metadata: [
                "volume": "\(name)",
                "error": "\(error)"
            ])
            throw VolumeError.failedToCreate(error.localizedDescription)
        }
    }

    /// Get volume path
    public func getVolumePath(name: String) throws -> URL {
        guard let info = volumes[name] else {
            throw VolumeError.notFound(name)
        }
        return info.mountPath
    }

    /// Remove volume
    public func removeVolume(name: String) async throws {
        // Check in-memory state first
        if let info = volumes[name] {
            guard !info.isExternal else {
                logger.debug("Skipping external volume", metadata: ["volume": "\(name)"])
                volumes.removeValue(forKey: name)
                return
            }

            logger.info("Removing volume", metadata: ["volume": "\(name)"])

            do {
                try FileManager.default.removeItem(at: info.mountPath)
                volumes.removeValue(forKey: name)
            } catch {
                logger.error("Failed to remove volume", metadata: [
                    "volume": "\(name)",
                    "error": "\(error)"
                ])
                throw VolumeError.failedToCreate(error.localizedDescription)
            }
        } else {
            // Volume not in memory, check filesystem
            let volumePath = volumesDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: volumePath.path) {
                logger.info("Removing volume from filesystem", metadata: [
                    "volume": "\(name)",
                    "path": "\(volumePath.path)"
                ])

                do {
                    try FileManager.default.removeItem(at: volumePath)
                } catch {
                    logger.error("Failed to remove volume", metadata: [
                        "volume": "\(name)",
                        "error": "\(error)"
                    ])
                    throw VolumeError.failedToCreate(error.localizedDescription)
                }
            } else {
                logger.debug("Volume does not exist in memory or filesystem", metadata: ["volume": "\(name)"])
            }
        }
    }

    /// Parse volume mount string (source:target[:ro])
    public func parseVolumeMount(_ mount: String) -> (source: String, target: String, readOnly: Bool) {
        let parts = mount.split(separator: ":")
        guard parts.count >= 2 else {
            return (mount, mount, false)
        }

        let source = String(parts[0])
        let target = String(parts[1])
        let readOnly = parts.count > 2 && parts[2] == "ro"

        return (source, target, readOnly)
    }

    /// Resolve bind mount path
    public func resolveBindMount(_ path: String, relativeTo baseDir: String) throws -> URL {
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else if path.hasPrefix("~") {
            let expandedPath = NSString(string: path).expandingTildeInPath
            url = URL(fileURLWithPath: expandedPath)
        } else {
            url = URL(fileURLWithPath: baseDir).appendingPathComponent(path)
        }

        // Verify path exists for bind mounts
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VolumeError.invalidPath(url.path)
        }

        return url
    }

    /// List all volumes
    public func listVolumes() -> [String: VolumeInfo] {
        return volumes
    }
}
