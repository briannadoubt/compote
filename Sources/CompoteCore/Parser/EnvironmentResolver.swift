import Foundation

/// Resolves environment variables in compose file values
public struct EnvironmentResolver: Sendable {
    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    /// Resolve environment variables in a string
    /// Supports ${VAR}, ${VAR:-default}, $VAR
    public func resolve(_ string: String) -> String {
        var result = string

        // Pattern: ${VAR} or ${VAR:-default}
        let pattern = #"\$\{([A-Za-z_][A-Za-z0-9_]*)(:-([^}]*))?\}"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(
                in: result,
                range: NSRange(result.startIndex..., in: result)
            )

            // Process in reverse to maintain string indices
            for match in matches.reversed() {
                guard let varRange = Range(match.range(at: 1), in: result) else { continue }
                let varName = String(result[varRange])

                let value: String
                if match.range(at: 3).location != NSNotFound,
                   let defaultRange = Range(match.range(at: 3), in: result) {
                    // Has default value
                    let defaultValue = String(result[defaultRange])
                    value = environment[varName] ?? defaultValue
                } else {
                    // No default
                    value = environment[varName] ?? ""
                }

                if let fullRange = Range(match.range, in: result) {
                    result.replaceSubrange(fullRange, with: value)
                }
            }
        }

        // Pattern: $VAR (simple)
        let simplePattern = #"\$([A-Za-z_][A-Za-z0-9_]*)"#
        if let regex = try? NSRegularExpression(pattern: simplePattern) {
            let matches = regex.matches(
                in: result,
                range: NSRange(result.startIndex..., in: result)
            )

            for match in matches.reversed() {
                guard let varRange = Range(match.range(at: 1), in: result) else { continue }
                let varName = String(result[varRange])
                let value = environment[varName] ?? ""

                if let fullRange = Range(match.range, in: result) {
                    result.replaceSubrange(fullRange, with: value)
                }
            }
        }

        return result
    }

    /// Load environment variables from .env file
    public static func loadEnvFile(at path: String) throws -> [String: String] {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        var env: [String: String] = [:]

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            guard !trimmed.isEmpty && !trimmed.hasPrefix("#") else { continue }

            // Parse KEY=VALUE
            if let index = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<index]).trimmingCharacters(in: .whitespaces)
                var value = String(trimmed[trimmed.index(after: index)...]).trimmingCharacters(in: .whitespaces)

                // Remove quotes if present
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }

                env[key] = value
            }
        }

        return env
    }

    /// Merge multiple environment sources
    public static func mergeEnvironments(_ environments: [[String: String]]) -> [String: String] {
        var result: [String: String] = [:]
        for env in environments {
            result.merge(env) { _, new in new }
        }
        return result
    }
}
