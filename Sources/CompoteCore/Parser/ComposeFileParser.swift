import Foundation
import Yams

public enum ComposeFileParserError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case invalidYAML(Error)
    case missingServices
    case circularDependency([String])

    public var description: String {
        switch self {
        case .fileNotFound(let path):
            return "Compose file not found: \(path)"
        case .invalidYAML(let error):
            return "Invalid YAML: \(error)"
        case .missingServices:
            return "No services defined in compose file"
        case .circularDependency(let cycle):
            return "Circular dependency detected: \(cycle.joined(separator: " -> "))"
        }
    }
}

public struct ComposeFileParser: Sendable {
    public init() {}

    /// Parse compose file from path, auto-detecting format
    public func parse(from path: String) throws -> ComposeFile {
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ComposeFileParserError.fileNotFound(path)
        }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return try parse(yaml: content)
    }

    /// Parse compose file from YAML string
    public func parse(yaml: String) throws -> ComposeFile {
        let decoder = YAMLDecoder()
        do {
            let composeFile = try decoder.decode(ComposeFile.self, from: yaml)
            try validate(composeFile)
            return composeFile
        } catch {
            throw ComposeFileParserError.invalidYAML(error)
        }
    }

    /// Find compose file in current directory
    public func findComposeFile(in directory: String = FileManager.default.currentDirectoryPath) -> String? {
        let candidates = [
            "compote.yml",
            "compote.yaml",
            "docker-compose.yml",
            "docker-compose.yaml"
        ]

        for candidate in candidates {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(candidate).path
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    /// Validate compose file structure
    private func validate(_ composeFile: ComposeFile) throws {
        guard !composeFile.services.isEmpty else {
            throw ComposeFileParserError.missingServices
        }

        // Check for circular dependencies
        try checkCircularDependencies(composeFile.services)
    }

    /// Check for circular dependencies using DFS
    private func checkCircularDependencies(_ services: [String: Service]) throws {
        var visited: Set<String> = []
        var recursionStack: Set<String> = []

        func dfs(_ serviceName: String, path: [String]) throws {
            visited.insert(serviceName)
            recursionStack.insert(serviceName)

            let currentPath = path + [serviceName]

            if let service = services[serviceName],
               let dependsOn = service.depends_on {
                for (dependency, _) in dependsOn.dependencies {
                    if !visited.contains(dependency) {
                        try dfs(dependency, path: currentPath)
                    } else if recursionStack.contains(dependency) {
                        throw ComposeFileParserError.circularDependency(currentPath + [dependency])
                    }
                }
            }

            recursionStack.remove(serviceName)
        }

        for serviceName in services.keys {
            if !visited.contains(serviceName) {
                try dfs(serviceName, path: [])
            }
        }
    }
}
