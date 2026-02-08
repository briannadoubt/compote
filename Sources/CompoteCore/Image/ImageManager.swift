import Foundation
import ContainerizationOCI
import Logging

public enum ImageError: Error, CustomStringConvertible {
    case failedToPull(String)
    case failedToBuild(String)
    case failedToPush(String)
    case notFound(String)
    case invalidReference(String)

    public var description: String {
        switch self {
        case .failedToPull(let msg):
            return "Failed to pull image: \(msg)"
        case .failedToBuild(let msg):
            return "Failed to build image: \(msg)"
        case .failedToPush(let msg):
            return "Failed to push image: \(msg)"
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
        let canonicalReference = Self.canonicalImageReference(reference)

        // Check if already tracked
        if let existing = images[canonicalReference] {
            logger.debug("Image reference already tracked", metadata: ["image": "\(canonicalReference)"])
            return existing.localPath
        }

        logger.info("Registering image reference", metadata: ["image": "\(canonicalReference)"])

        let parsed = parseImageReference(canonicalReference)
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
                reference: canonicalReference,
                digest: nil,
                size: 0,
                localPath: imagePath
            )
            images[canonicalReference] = info

            logger.info("Image reference registered", metadata: [
                "image": "\(canonicalReference)",
                "path": "\(imagePath.path)"
            ])

            return imagePath
        } catch {
            logger.error("Failed to register image", metadata: [
                "image": "\(canonicalReference)",
                "error": "\(error)"
            ])
            throw ImageError.failedToPull(error.localizedDescription)
        }
    }

    /// Build image from Dockerfile using Docker
    public func buildImage(
        context: String,
        dockerfile: String = "Dockerfile",
        tag: String,
        buildArgs: [String: String] = [:]
    ) async throws -> URL {
        logger.info("Building image from Dockerfile", metadata: [
            "context": "\(context)",
            "dockerfile": "\(dockerfile)",
            "tag": "\(tag)"
        ])

        // Resolve context path
        let contextPath: String
        if context.hasPrefix("/") {
            contextPath = context
        } else if context.hasPrefix("~") {
            contextPath = NSString(string: context).expandingTildeInPath
        } else {
            // Relative path - resolve from current directory
            let cwd = FileManager.default.currentDirectoryPath
            contextPath = URL(fileURLWithPath: cwd).appendingPathComponent(context).path
        }

        let contextURL = URL(fileURLWithPath: contextPath)
        let dockerfileURL = contextURL.appendingPathComponent(dockerfile)

        // Verify Dockerfile exists
        guard FileManager.default.fileExists(atPath: dockerfileURL.path) else {
            throw ImageError.failedToBuild("Dockerfile not found at \(dockerfileURL.path)")
        }

        // Check if docker is available
        let dockerCheckProcess = Process()
        dockerCheckProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        dockerCheckProcess.arguments = ["which", "docker"]

        let checkPipe = Pipe()
        dockerCheckProcess.standardOutput = checkPipe
        dockerCheckProcess.standardError = Pipe()

        do {
            try dockerCheckProcess.run()
            dockerCheckProcess.waitUntilExit()

            guard dockerCheckProcess.terminationStatus == 0 else {
                throw ImageError.failedToBuild("Docker is not installed or not in PATH. Please install Docker to build images.")
            }
        } catch {
            throw ImageError.failedToBuild("Failed to check for Docker: \(error.localizedDescription)")
        }

        // Build docker build command
        var args = ["docker", "build"]
        args.append(contentsOf: ["-t", tag])
        args.append(contentsOf: ["-f", dockerfileURL.path])

        // Add build args
        for (key, value) in buildArgs {
            args.append("--build-arg")
            args.append("\(key)=\(value)")
        }

        args.append(contextPath)

        // Run docker build
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        logger.debug("Running docker build", metadata: [
            "command": "\(args.joined(separator: " "))"
        ])

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                logger.error("Docker build failed", metadata: [
                    "exitCode": "\(process.terminationStatus)",
                    "output": "\(output)",
                    "error": "\(errorOutput)"
                ])
                throw ImageError.failedToBuild("Docker build failed with exit code \(process.terminationStatus): \(errorOutput)")
            }

            logger.info("Image built successfully", metadata: [
                "tag": "\(tag)"
            ])

            // Register the built image locally
            let parsed = parseImageReference(tag)
            let imagePath = imagesDir
                .appendingPathComponent(parsed.name.replacingOccurrences(of: "/", with: "_"))
                .appendingPathComponent(parsed.tag)

            // Create directory for the image
            try FileManager.default.createDirectory(
                at: imagePath,
                withIntermediateDirectories: true
            )

            // Store image info
            let info = ImageInfo(
                reference: tag,
                digest: nil,  // Built images don't have digest until pushed
                size: 0,  // Size not immediately available for built images
                localPath: imagePath
            )
            images[tag] = info

            logger.info("Image registered", metadata: [
                "tag": "\(tag)",
                "path": "\(imagePath.path)"
            ])

            return imagePath
        } catch {
            logger.error("Failed to build image", metadata: [
                "context": "\(context)",
                "error": "\(error)"
            ])
            throw ImageError.failedToBuild(error.localizedDescription)
        }
    }

    /// Get image path
    public func getImagePath(reference: String) throws -> URL {
        guard let info = images[reference] else {
            throw ImageError.notFound(reference)
        }
        return info.localPath
    }

    /// Push image to remote registry using Docker
    public func pushImage(reference: String) async throws {
        let canonicalReference = Self.canonicalImageReference(reference)

        logger.info("Pushing image", metadata: [
            "image": "\(canonicalReference)"
        ])

        // Check if docker is available
        let dockerCheckProcess = Process()
        dockerCheckProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        dockerCheckProcess.arguments = ["which", "docker"]
        dockerCheckProcess.standardOutput = Pipe()
        dockerCheckProcess.standardError = Pipe()

        do {
            try dockerCheckProcess.run()
            dockerCheckProcess.waitUntilExit()

            guard dockerCheckProcess.terminationStatus == 0 else {
                throw ImageError.failedToPush("Docker is not installed or not in PATH. Please install Docker to push images.")
            }
        } catch {
            throw ImageError.failedToPush("Failed to check for Docker: \(error.localizedDescription)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["docker", "push", canonicalReference]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                logger.error("Docker push failed", metadata: [
                    "image": "\(reference)",
                    "canonicalImage": "\(canonicalReference)",
                    "exitCode": "\(process.terminationStatus)",
                    "output": "\(output)",
                    "error": "\(errorOutput)"
                ])
                throw ImageError.failedToPush("Docker push failed with exit code \(process.terminationStatus): \(errorOutput)")
            }

            logger.info("Image pushed", metadata: [
                "image": "\(canonicalReference)"
            ])
        } catch {
            throw ImageError.failedToPush(error.localizedDescription)
        }
    }

    /// Convert Docker-style shorthand to fully-qualified OCI references.
    /// Examples:
    /// - nginx -> docker.io/library/nginx:latest
    /// - nginx:alpine -> docker.io/library/nginx:alpine
    /// - org/app:1.0 -> docker.io/org/app:1.0
    public nonisolated static func canonicalImageReference(_ reference: String) -> String {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return reference }
        if trimmed.contains("@sha256:") { return trimmed }

        let parsed = parseReferenceComponents(trimmed)
        let firstPathComponent = parsed.path.split(separator: "/").first.map(String.init) ?? parsed.path
        let hasRegistry = firstPathComponent.contains(".")
            || firstPathComponent.contains(":")
            || firstPathComponent == "localhost"

        let normalizedPath: String
        if hasRegistry {
            normalizedPath = parsed.path
        } else if parsed.path.contains("/") {
            normalizedPath = "docker.io/\(parsed.path)"
        } else {
            normalizedPath = "docker.io/library/\(parsed.path)"
        }

        return "\(normalizedPath):\(parsed.tag)"
    }

    private nonisolated static func parseReferenceComponents(_ reference: String) -> (path: String, tag: String) {
        // If there is a colon after the last slash, treat it as a tag delimiter.
        if
            let slash = reference.lastIndex(of: "/"),
            let colon = reference[slash...].lastIndex(of: ":")
        {
            let path = String(reference[..<colon])
            let tag = String(reference[reference.index(after: colon)...])
            return (path, tag)
        }

        if !reference.contains("/"), let colon = reference.lastIndex(of: ":") {
            let path = String(reference[..<colon])
            let tag = String(reference[reference.index(after: colon)...])
            return (path, tag)
        }

        return (reference, "latest")
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
