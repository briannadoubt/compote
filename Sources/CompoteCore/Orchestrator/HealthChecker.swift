import Foundation
import Logging

public enum HealthStatus: Sendable {
    case starting
    case healthy
    case unhealthy
}

/// Monitors service health checks
public actor HealthChecker {
    private var healthStatus: [String: HealthStatus] = [:]
    private let logger: Logger

    public init(logger: Logger) {
        self.logger = logger
    }

    /// Run health check for a service
    public func runHealthCheck(
        serviceName: String,
        healthCheck: HealthCheck,
        container: ContainerRuntime
    ) async throws -> HealthStatus {
        guard let test = healthCheck.test else {
            // No health check defined, consider healthy
            healthStatus[serviceName] = .healthy
            return .healthy
        }

        let interval = parseDuration(healthCheck.interval ?? "30s")
        let timeout = parseDuration(healthCheck.timeout ?? "30s")
        let retries = healthCheck.retries ?? 3
        let startPeriod = parseDuration(healthCheck.start_period ?? "0s")

        logger.info("Starting health check", metadata: [
            "service": "\(serviceName)",
            "interval": "\(interval)",
            "retries": "\(retries)"
        ])

        // Set initial status
        healthStatus[serviceName] = .starting

        // Wait for start period
        if startPeriod > 0 {
            try await Task.sleep(for: .seconds(startPeriod))
        }

        // Retry loop
        var attempts = 0
        var consecutiveFailures = 0

        while attempts < retries {
            do {
                let command = test.asArray

                logger.debug("Running health check command", metadata: [
                    "service": "\(serviceName)",
                    "command": "\(command.joined(separator: " "))",
                    "attempt": "\(attempts + 1)"
                ])

                let exitCode = try await container.exec(
                    command: command,
                    environment: [:]
                )

                if exitCode == 0 {
                    logger.info("Health check passed", metadata: [
                        "service": "\(serviceName)"
                    ])
                    healthStatus[serviceName] = .healthy
                    return .healthy
                } else {
                    consecutiveFailures += 1
                    logger.warning("Health check failed", metadata: [
                        "service": "\(serviceName)",
                        "exitCode": "\(exitCode)",
                        "failures": "\(consecutiveFailures)"
                    ])
                }
            } catch {
                consecutiveFailures += 1
                logger.error("Health check error", metadata: [
                    "service": "\(serviceName)",
                    "error": "\(error)",
                    "failures": "\(consecutiveFailures)"
                ])
            }

            attempts += 1

            if attempts < retries {
                try await Task.sleep(for: .seconds(interval))
            }
        }

        logger.error("Health check failed after retries", metadata: [
            "service": "\(serviceName)",
            "retries": "\(retries)"
        ])

        healthStatus[serviceName] = .unhealthy
        return .unhealthy
    }

    /// Get current health status
    public func getStatus(serviceName: String) -> HealthStatus {
        return healthStatus[serviceName] ?? .starting
    }

    /// Wait for service to become healthy
    public func waitForHealthy(
        serviceName: String,
        timeout: Duration = .seconds(60)
    ) async throws {
        let deadline = Date.now.addingTimeInterval(TimeInterval(timeout.components.seconds))

        while Date.now < deadline {
            let status = healthStatus[serviceName] ?? .starting

            switch status {
            case .healthy:
                return
            case .unhealthy:
                throw HealthCheckError.unhealthy(serviceName)
            case .starting:
                try await Task.sleep(for: .seconds(1))
            }
        }

        throw HealthCheckError.timeout(serviceName)
    }

    /// Parse duration string (e.g., "30s", "1m", "1h")
    private func parseDuration(_ duration: String) -> Int {
        let value = duration.dropLast()
        let unit = duration.last

        guard let number = Int(value) else { return 30 }

        switch unit {
        case "s":
            return number
        case "m":
            return number * 60
        case "h":
            return number * 3600
        default:
            return 30
        }
    }
}

public enum HealthCheckError: Error, CustomStringConvertible {
    case timeout(String)
    case unhealthy(String)

    public var description: String {
        switch self {
        case .timeout(let service):
            return "Health check timeout for service: \(service)"
        case .unhealthy(let service):
            return "Service is unhealthy: \(service)"
        }
    }
}
