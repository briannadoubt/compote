import Foundation
import ContainerizationOCI
import Logging

public enum ImageError: Error, CustomStringConvertible {
    case failedToPull(String)
    case failedToBuild(String)
    case notFound(String)
    case invalidReference(String)

    public var description: String {
        switch self {
        case .failedToPull(let msg):
            return "Failed to pull image: \(msg)"
        case .failedToBuild(let msg):
            return "Failed to build image: \(msg)"
        case .notFound(let ref):
            return "Image not found: \(ref)"
        case .invalidReference(let ref):
            return "Invalid image reference: \(ref)"
        }
    }
}

/// Manages OCI images
public actor ImageManager {
    private var images: [String: ImageInfo] = [:]
    private let imagesDir: URL
    private let logger: Logger

    public struct ImageInfo: Sendable {
        public let reference: String
        public let digest: String?
        public let size: Int64
        public let localPath: URL
    }

    public init(logger: Logger) throws {
        self.logger = logger

        // Store images in ~/Library/Application Support/compote/images
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        self.imagesDir = appSupport
            .appendingPathComponent("compote")
            .appendingPathComponent("images")

        // Create images directory
        try FileManager.default.createDirectory(
            at: imagesDir,
            withIntermediateDirectories: true
        )
    }

    /// Pull an OCI image from registry
    /// Note: Actual pulling is handled by ContainerManager.
    /// This method just tracks that we've requested this image.
    public func pullImage(reference: String) async throws -> URL {
        // Check if already tracked
        if let existing = images[reference] {
            logger.debug("Image reference already tracked", metadata: ["image": "\(reference)"])
            return existing.localPath
        }

        logger.info("Registering image reference", metadata: ["image": "\(reference)"])

        let parsed = parseImageReference(reference)
        let imagePath = imagesDir
            .appendingPathComponent(parsed.name.replacingOccurrences(of: "/", with: "_"))
            .appendingPathComponent(parsed.tag)

        do {
            // Create directory for tracking
            try FileManager.default.createDirectory(
                at: imagePath,
                withIntermediateDirectories: true
            )

            // Track the image reference
            // Actual OCI image pulling is handled by ContainerManager's ImageStore
            let info = ImageInfo(
                reference: reference,
                digest: nil,
                size: 0,
                localPath: imagePath
            )
            images[reference] = info

            logger.info("Image reference registered", metadata: [
                "image": "\(reference)",
                "path": "\(imagePath.path)"
            ])

            return imagePath
        } catch {
            logger.error("Failed to register image", metadata: [
                "image": "\(reference)",
                "error": "\(error)"
            ])
            throw ImageError.failedToPull(error.localizedDescription)
        }
    }

    /// Build image from Dockerfile
    /// Note: Dockerfile building is not yet implemented.
    /// This is a placeholder for future implementation.
    public func buildImage(
        context: String,
        dockerfile: String = "Dockerfile",
        tag: String
    ) async throws -> URL {
        logger.warning("Dockerfile building not yet implemented", metadata: [
            "context": "\(context)",
            "dockerfile": "\(dockerfile)",
            "tag": "\(tag)"
        ])

        let contextURL = URL(fileURLWithPath: context)
        let dockerfileURL = contextURL.appendingPathComponent(dockerfile)

        guard FileManager.default.fileExists(atPath: dockerfileURL.path) else {
            throw ImageError.failedToBuild("Dockerfile not found at \(dockerfileURL.path)")
        }

        // For now, throw an error indicating this is not yet supported
        throw ImageError.failedToBuild("Dockerfile building not yet implemented. Please use pre-built images from a registry.")
    }

    /// Get image path
    public func getImagePath(reference: String) throws -> URL {
        guard let info = images[reference] else {
            throw ImageError.notFound(reference)
        }
        return info.localPath
    }

    /// Parse image reference into components
    private func parseImageReference(_ reference: String) -> (registry: String?, name: String, tag: String) {
        var remaining = reference
        var registry: String? = nil

        // Check for registry
        if let slashIndex = remaining.firstIndex(of: "/"),
           remaining[..<slashIndex].contains(".") || remaining[..<slashIndex].contains(":") {
            registry = String(remaining[..<slashIndex])
            remaining = String(remaining[remaining.index(after: slashIndex)...])
        }

        // Split name and tag
        if let colonIndex = remaining.lastIndex(of: ":") {
            let name = String(remaining[..<colonIndex])
            let tag = String(remaining[remaining.index(after: colonIndex)...])
            return (registry, name, tag)
        } else {
            return (registry, remaining, "latest")
        }
    }

    /// List cached images
    public func listImages() -> [String: ImageInfo] {
        return images
    }
}
