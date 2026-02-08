import ArgumentParser
import CompoteCore
import Foundation
import Logging

struct ScaleCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scale",
        abstract: "Scale services to a desired replica count (e.g., web=3)"
    )

    @Option(name: .shortAndLong, help: "Path to compose file")
    var file: String?

    @Option(name: .shortAndLong, help: "Project name")
    var projectName: String?

    @Argument(help: "Scale targets in service=replicas format")
    var targets: [String] = []

    mutating func run() throws {
        let fileArg = file
        let projectNameArg = projectName
        let targetsArg = targets

        guard !targetsArg.isEmpty else {
            throw ValidationError("Provide at least one scale target, e.g. `compote scale web=3`")
        }

        let parsedTargets = try targetsArg.map(parseTarget)

        try runAsyncTask {
            var logger = Logger(label: "compote")
            logger.logLevel = .info

            let parser = ComposeFileParser()
            let composePath: String
            if let file = fileArg {
                composePath = file
            } else if let found = parser.findComposeFile() {
                composePath = found
            } else {
                throw CompoteError.noComposeFile
            }

            let composeFile = try parser.parse(from: composePath)
            let project = projectNameArg ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .lastPathComponent

            let orchestrator = try Orchestrator(
                composeFile: composeFile,
                projectName: project,
                logger: logger
            )

            for (service, replicas) in parsedTargets {
                try await orchestrator.scale(serviceName: service, replicas: replicas)
            }

            logger.info("Scale operation complete")
        }
    }

    private func parseTarget(_ target: String) throws -> (String, Int) {
        let parts = target.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            throw ValidationError("Invalid scale target '\(target)'. Expected format service=replicas.")
        }
        let service = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !service.isEmpty else {
            throw ValidationError("Service name cannot be empty in scale target '\(target)'.")
        }
        guard let replicas = Int(parts[1]), replicas >= 0 else {
            throw ValidationError("Replica count must be a non-negative integer in '\(target)'.")
        }
        return (service, replicas)
    }
}
