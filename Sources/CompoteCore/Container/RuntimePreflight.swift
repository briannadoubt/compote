import Foundation
#if canImport(Security)
import Security
#endif

public enum RuntimePreflightError: Error, CustomStringConvertible {
    case virtualizationEntitlementMissing(String)

    public var description: String {
        switch self {
        case .virtualizationEntitlementMissing(let executable):
            return """
            Missing required virtualization entitlement: com.apple.security.virtualization

            This binary cannot start Linux VMs required by Compote.

            Executable:
              \(executable)

            Verify entitlements:
              codesign -d --entitlements :- "\(executable)"

            Use a properly signed binary that includes virtualization entitlements before running:
              compote up
            """
        }
    }
}

public enum RuntimePreflight {
    public static func ensureVirtualizationEntitlement() throws {
        guard hasVirtualizationEntitlement() else {
            throw RuntimePreflightError.virtualizationEntitlementMissing(executablePath())
        }
    }

    public static func hasVirtualizationEntitlement() -> Bool {
        #if canImport(Security)
        guard let task = SecTaskCreateFromSelf(nil) else {
            return false
        }
        let key = "com.apple.security.virtualization" as CFString
        let value = SecTaskCopyValueForEntitlement(task, key, nil)
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let numberValue = value as? NSNumber {
            return numberValue.boolValue
        }
        return false
        #else
        return false
        #endif
    }

    public static func executablePath() -> String {
        ProcessInfo.processInfo.arguments.first ?? "compote"
    }
}
