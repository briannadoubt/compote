import Foundation

enum PortMappingParseError: Error, CustomStringConvertible {
    case unsupportedProtocol(String)
    case invalidFormat(String)

    var description: String {
        switch self {
        case .unsupportedProtocol(let spec):
            return "Unsupported protocol in port mapping '\(spec)'. Use tcp or udp."
        case .invalidFormat(let spec):
            return "Invalid port mapping '\(spec)'. Expected host:container[/proto] or ip:host:container[/proto]."
        }
    }
}

struct PortMapping: Equatable, Sendable {
    let hostIP: String
    let hostPort: Int
    let containerPort: Int
    let proto: String
}

enum PortMappingParser {
    static func parse(_ spec: String) throws -> PortMapping {
        let parts = spec.split(separator: "/", maxSplits: 1).map(String.init)
        let mappingPart = parts[0]
        let proto = parts.count > 1 ? parts[1].lowercased() : "tcp"
        guard proto == "tcp" || proto == "udp" else {
            throw PortMappingParseError.unsupportedProtocol(spec)
        }

        let fields = mappingPart.split(separator: ":").map(String.init)
        if fields.count == 2,
           let hostPort = Int(fields[0]),
           let containerPort = Int(fields[1]),
           (1...65535).contains(hostPort),
           (1...65535).contains(containerPort) {
            return PortMapping(
                hostIP: "0.0.0.0",
                hostPort: hostPort,
                containerPort: containerPort,
                proto: proto
            )
        }

        if fields.count == 3,
           let hostPort = Int(fields[1]),
           let containerPort = Int(fields[2]),
           (1...65535).contains(hostPort),
           (1...65535).contains(containerPort) {
            return PortMapping(
                hostIP: fields[0],
                hostPort: hostPort,
                containerPort: containerPort,
                proto: proto
            )
        }

        throw PortMappingParseError.invalidFormat(spec)
    }
}
