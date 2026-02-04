import Foundation

public enum DependencyError: Error, CustomStringConvertible {
    case circularDependency([String])
    case missingService(String)

    public var description: String {
        switch self {
        case .circularDependency(let cycle):
            return "Circular dependency detected: \(cycle.joined(separator: " -> "))"
        case .missingService(let name):
            return "Dependency references missing service: \(name)"
        }
    }
}

/// Resolves service dependencies and determines startup order
public struct DependencyResolver: Sendable {
    public init() {}

    /// Resolve dependencies and return services in startup order
    public func resolveStartupOrder(services: [String: Service]) throws -> [[String]] {
        // Build dependency graph
        var graph: [String: Set<String>] = [:]
        var inDegree: [String: Int] = [:]

        // Initialize
        for serviceName in services.keys {
            graph[serviceName] = []
            inDegree[serviceName] = 0
        }

        // Build edges (service -> depends on)
        for (serviceName, service) in services {
            if let dependsOn = service.depends_on {
                for (dependency, _) in dependsOn.dependencies {
                    guard services[dependency] != nil else {
                        throw DependencyError.missingService(dependency)
                    }

                    graph[dependency, default: []].insert(serviceName)
                    inDegree[serviceName, default: 0] += 1
                }
            }
        }

        // Topological sort using Kahn's algorithm
        var result: [[String]] = []
        var queue = services.keys.filter { inDegree[$0] == 0 }.sorted()
        var visited = Set<String>()

        while !queue.isEmpty {
            // Process all services with no dependencies as one batch (parallel)
            let batch = queue
            result.append(batch)

            var nextQueue: [String] = []

            for serviceName in batch {
                visited.insert(serviceName)

                // Reduce in-degree for dependent services
                for dependent in graph[serviceName, default: []] {
                    inDegree[dependent, default: 0] -= 1

                    if inDegree[dependent] == 0 && !visited.contains(dependent) {
                        nextQueue.append(dependent)
                    }
                }
            }

            queue = nextQueue.sorted()
        }

        // Check if all services were visited (no cycles)
        if visited.count != services.count {
            let unvisited = services.keys.filter { !visited.contains($0) }
            throw DependencyError.circularDependency(Array(unvisited))
        }

        return result
    }

    /// Get services that depend on health check
    public func getHealthDependencies(services: [String: Service]) -> [String: Set<String>] {
        var healthDeps: [String: Set<String>] = [:]

        for (serviceName, service) in services {
            if let dependsOn = service.depends_on {
                for (dependency, condition) in dependsOn.dependencies {
                    if condition.condition == "service_healthy" {
                        healthDeps[dependency, default: []].insert(serviceName)
                    }
                }
            }
        }

        return healthDeps
    }
}
