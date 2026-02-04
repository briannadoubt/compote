import ArgumentParser
import CompoteCore
import Foundation
import Logging

struct ExecCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "exec",
        abstract: "Execute a command in a running container"
    )

    @Option(name: .shortAndLong, help: "Path to compose file")
    var file: String?

    @Option(name: .shortAndLong, help: "Project name")
    var projectName: String?

    @Argument(help: "Service name")
    var service: String

    @Argument(parsing: .remaining, help: "Command to execute")
    var command: [String] = []

    mutating func run() throws {
        print("Exec command not yet implemented")
        // TODO: Implement exec
    }
}
