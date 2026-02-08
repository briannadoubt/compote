import ArgumentParser
import CompoteCore
import Foundation
import Logging

struct LogsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logs",
        abstract: "View output from containers"
    )

    @Option(name: .shortAndLong, help: "Path to compose file")
    var file: String?

    @Option(name: .shortAndLong, help: "Project name")
    var projectName: String?

    @Flag(name: .shortAndLong, help: "Follow log output")
    var follow = false

    @Option(name: .shortAndLong, help: "Number of lines to show from the end of the logs")
    var tail: Int?

    @Flag(name: .shortAndLong, help: "Show timestamps")
    var timestamps = false

    @Argument(help: "Service selectors (service or service#replica)")
    var services: [String] = []

    mutating func run() throws {
        // Capture values before async context
        let fileArg = file
        let projectNameArg = projectName
        let servicesArg = services
        let timestampsFlag = timestamps
        let followFlag = follow
        let tailArg = tail

        if let tailArg, tailArg < 0 {
            throw ValidationError("--tail must be a non-negative integer")
        }

        try runAsyncTask {
            // Setup logger
            var logger = Logger(label: "compote")
            logger.logLevel = .warning  // Quiet logger for logs command

            // Find compose file
            let parser = ComposeFileParser()
            let composePath: String
            if let file = fileArg {
                composePath = file
            } else if let found = parser.findComposeFile() {
                composePath = found
            } else {
                throw CompoteError.noComposeFile
            }

            // Parse compose file
            let composeFile = try parser.parse(from: composePath)

            // Determine project name
            let project = projectNameArg ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .lastPathComponent

            // Create orchestrator
            let orchestrator = try Orchestrator(
                composeFile: composeFile,
                projectName: project,
                logger: logger
            )

            // Check service statuses
            let serviceStatuses = await orchestrator.listServiceStatuses()
            let runningServices = serviceStatuses
                .filter { $0.isRunning }
                .map { $0.name }
            let knownStoppedServices = serviceStatuses
                .filter { !$0.isRunning && $0.isKnown }
                .map { $0.name }

            guard !runningServices.isEmpty else {
                if knownStoppedServices.isEmpty {
                    logger.error("No running containers found")
                } else {
                    logger.error("No running containers found. Known stopped services: \(knownStoppedServices.joined(separator: ", ")). Start them with `compote start` or `compote up -d`.")
                }
                throw CompoteError.noRunningContainers
            }

            // Determine which services to show logs for
            let servicesToShow: [String]
            if servicesArg.isEmpty {
                servicesToShow = runningServices
            } else {
                servicesToShow = servicesArg.filter {
                    runningServices.contains(Self.baseServiceName(for: $0))
                }
                let notRunning = servicesArg.filter {
                    !runningServices.contains(Self.baseServiceName(for: $0))
                }
                if !notRunning.isEmpty {
                    logger.warning("Services not running: \(notRunning.joined(separator: ", "))")
                }
            }

            guard !servicesToShow.isEmpty else {
                logger.error("None of the specified services are running")
                throw CompoteError.noRunningContainers
            }

            // Stream logs
            let logStream = try await orchestrator.streamLogs(
                services: servicesToShow,
                includeStderr: true,
                tail: tailArg,
                follow: followFlag
            )

            // Format and print logs
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

            for await line in logStream {
                if timestampsFlag {
                    let timestamp = formatter.string(from: Date())
                    print("\(timestamp) \(line)", terminator: "")
                } else {
                    print(line, terminator: "")
                }
            }
        }
    }

    private static func baseServiceName(for selector: String) -> String {
        selector.split(separator: "#", maxSplits: 1).first.map(String.init) ?? selector
    }
}
