import ArgumentParser
import CompoteCore
import Foundation
import Logging

struct StartCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start existing containers"
    )

    @Option(name: .shortAndLong, help: "Path to compose file")
    var file: String?

    @Option(name: .shortAndLong, help: "Project name")
    var projectName: String?

    @Argument(help: "Service names")
    var services: [String] = []

    mutating func run() throws {
        print("Start command not yet implemented")
        // TODO: Implement start for existing stopped containers
    }
}
