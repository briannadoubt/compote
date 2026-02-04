import ArgumentParser
import CompoteCore
import Foundation
import Logging

struct RestartCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restart",
        abstract: "Restart containers"
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
        print("Restart command not yet implemented")
        // TODO: Implement restart
    }
}
