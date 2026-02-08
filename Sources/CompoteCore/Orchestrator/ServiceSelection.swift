import Foundation

enum ServiceSelectionError: Error, CustomStringConvertible {
    case invalidSelector(String)
    case unknownService(String)

    var description: String {
        switch self {
        case .invalidSelector(let value):
            return "Invalid service selector '\(value)'. Use service or service#replica (for example: web or web#2)."
        case .unknownService(let service):
            return "Service not found: \(service)"
        }
    }
}

struct ServiceSelector: Equatable, Sendable {
    let serviceName: String
    let replicaIndex: Int?

    static func parse(_ value: String) throws -> ServiceSelector {
        let parts = value.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).map(String.init)
        guard let serviceName = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !serviceName.isEmpty else {
            throw ServiceSelectionError.invalidSelector(value)
        }

        if parts.count == 1 {
            return ServiceSelector(serviceName: serviceName, replicaIndex: nil)
        }

        guard let replicaIndex = Int(parts[1]), replicaIndex > 0 else {
            throw ServiceSelectionError.invalidSelector(value)
        }

        return ServiceSelector(serviceName: serviceName, replicaIndex: replicaIndex)
    }
}

enum ReplicaSelection: Equatable, Sendable {
    case all
    case indices(Set<Int>)
}

struct ServiceSelections: Equatable, Sendable {
    let values: [String: ReplicaSelection]

    static func parse(
        _ selectors: [String],
        validServices: Set<String>? = nil
    ) throws -> ServiceSelections {
        var selections: [String: ReplicaSelection] = [:]

        for raw in selectors {
            let selector = try ServiceSelector.parse(raw)

            if let validServices, !validServices.contains(selector.serviceName) {
                throw ServiceSelectionError.unknownService(selector.serviceName)
            }

            if let replicaIndex = selector.replicaIndex {
                if case .all = selections[selector.serviceName] {
                    continue
                }
                if case .indices(let existing) = selections[selector.serviceName] {
                    selections[selector.serviceName] = .indices(existing.union([replicaIndex]))
                } else {
                    selections[selector.serviceName] = .indices([replicaIndex])
                }
            } else {
                selections[selector.serviceName] = .all
            }
        }

        return ServiceSelections(values: selections)
    }
}
