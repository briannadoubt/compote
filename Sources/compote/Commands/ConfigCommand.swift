import ArgumentParser
import CompoteCore
import Foundation
import Logging

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Validate and view the Compose file"
    )

    @Option(name: .shortAndLong, help: "Path to compose file")
    var file: String?

    @Flag(help: "Don't resolve environment variables")
    var noInterpolate = false

    mutating func run() throws {
        // Capture values before async context
        let fileArg = file

        try runAsyncTask {
            // Setup logger
            var logger = Logger(label: "compote")
            logger.logLevel = .warning

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

            // Print summary
            print("Services:")
            for (name, service) in composeFile.services.sorted(by: { $0.key < $1.key }) {
                print("  \(name):")
                if let image = service.image {
                    print("    image: \(image)")
                }
                if let build = service.build {
                    print("    build: \(build.context ?? ".")")
                }
                if let ports = service.ports {
                    print("    ports:")
                    for port in ports {
                        print("      - \(port)")
                    }
                }
            }

            if let networks = composeFile.networks {
                print("\nNetworks:")
                for (name, network) in networks.sorted(by: { $0.key < $1.key }) {
                    print("  \(name):")
                    if let driver = network.driver {
                        print("    driver: \(driver)")
                    }
                }
            }

            if let volumes = composeFile.volumes {
                print("\nVolumes:")
                for (name, _) in volumes.sorted(by: { $0.key < $1.key }) {
                    print("  \(name)")
                }
            }
        }
    }
}
