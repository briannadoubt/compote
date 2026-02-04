import Foundation

/// External can be bool or object
public enum External: Codable, Sendable {
    case bool(Bool)
    case object(ExternalConfig)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let object = try? container.decode(ExternalConfig.self) {
            self = .object(object)
        } else {
            throw DecodingError.typeMismatch(
                External.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected bool or object"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let bool):
            try container.encode(bool)
        case .object(let object):
            try container.encode(object)
        }
    }

    public var isExternal: Bool {
        switch self {
        case .bool(let value):
            return value
        case .object:
            return true
        }
    }
}

public struct ExternalConfig: Codable, Sendable {
    public let name: String?

    public init(name: String? = nil) {
        self.name = name
    }
}
