import ArgumentParser
import CompoteCore
import Foundation
import Logging

struct StopCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop running containers without removing them"
    )

    @Option(name: .shortAndLong, help: "Path to compose file")
    var file: String?

    @Option(name: .shortAndLong, help: "Project name")
    var projectName: String?

    @Option(name: .shortAndLong, help: "Timeout in seconds to wait for stop")
    var timeout: Int = 10

    @Argument(help: "Service names")
    var services: [String] = []

    mutating func run() throws {
        print("Stop command not yet implemented")
        // TODO: Implement stop without removal
    }
}
