import ArgumentParser
import CompoteCore
import Foundation
import Logging

struct SetupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Check Compote setup and display installation instructions"
    )

    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose = false

    func run() throws {
        try runAsyncTask {
        var logger = Logger(label: "compote.setup")
        logger.logLevel = verbose ? .debug : .info

        print("🔍 Checking Compote setup...\n")

        // Check kernel availability
        let kernelManager = try KernelManager(logger: logger)
        let kernelAvailable = await kernelManager.checkKernelAvailable()

        if kernelAvailable {
            print("✅ Linux kernel: Found")
            if verbose {
                if let kernel = try? await kernelManager.getKernel() {
                    print("   Path: \(kernel.path.path)")
                    print("   Platform: \(kernel.platform)")
                }
            }
        } else {
            print("❌ Linux kernel: Not found")
            print("\n📋 Setup Instructions:")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print(kernelManager.getSetupInstructions())
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            throw ExitCode.failure
        }

        // Check virtualization entitlement required for VM startup
        if RuntimePreflight.hasVirtualizationEntitlement() {
            print("✅ Virtualization entitlement: Present")
        } else {
            print("❌ Virtualization entitlement: Missing")
            print("   Required entitlement: com.apple.security.virtualization")
            print("   Binary: \(RuntimePreflight.executablePath())")
            print("   Check with: codesign -d --entitlements :- \"\(RuntimePreflight.executablePath())\"")
            throw ExitCode.failure
        }

        // Check macOS version for vmnet support
        if #available(macOS 26, *) {
            print("✅ Networking: vmnet supported (macOS 26+)")
        } else {
            print("⚠️  Networking: Limited (requires macOS 26+ for vmnet)")
            print("   Containers will run without networking on this macOS version")
        }

        // Check directories
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let compoteDir = appSupport.appendingPathComponent("compote")

        if FileManager.default.fileExists(atPath: compoteDir.path) {
            print("✅ Storage directory: \(compoteDir.path)")
        } else {
            print("ℹ️  Storage directory will be created on first run")
            print("   Location: \(compoteDir.path)")
        }

        print("\n✨ Setup check complete!")
        print("\nYou can now run: compote up")
        }
    }
}
