import Foundation
import Containerization
import ContainerizationOCI
import Logging

public enum KernelError: Error, CustomStringConvertible {
    case kernelNotFound
    case initfsNotFound
    case downloadFailed(String)
    case invalidPlatform

    public var description: String {
        switch self {
        case .kernelNotFound:
            return """
            Linux kernel not found.

            Compote requires a Linux kernel to run containers. You can obtain one by:

            1. Using Homebrew (recommended):
               brew install --cask --no-quarantine containerization
               # This installs Apple's containerization tools with a kernel

            2. Building from source:
               git clone https://github.com/apple/containerization.git
               cd containerization/kernel
               make
               # Then copy the built kernel to /usr/local/share/containerization/kernel/

            3. Using an existing kernel:
               Place your Linux kernel at one of these locations:
               - /usr/share/containerization/kernel/vmlinuz
               - /opt/homebrew/share/containerization/kernel/vmlinuz
               - /usr/local/share/containerization/kernel/vmlinuz
               - ~/Library/Application Support/compote/kernel/vmlinuz-arm64

            For more information, visit: https://github.com/apple/containerization
            """
        case .initfsNotFound:
            return "Init filesystem not found."
        case .downloadFailed(let msg):
            return "Failed to download kernel/initfs: \(msg)"
        case .invalidPlatform:
            return "Unsupported platform. Compote requires ARM64 (Apple Silicon) or x86_64 (Intel Mac)."
        }
    }
}

/// Manages Linux kernel and initfs for VM boot
public actor KernelManager {
    private let kernelDir: URL
    private let logger: Logger
    private var cachedKernel: Kernel?
    private var cachedInitfsReference: String?

    public init(logger: Logger) throws {
        self.logger = logger

        // Store kernel in ~/Library/Application Support/compote/kernel
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        self.kernelDir = appSupport
            .appendingPathComponent("compote")
            .appendingPathComponent("kernel")

        // Create kernel directory
        try FileManager.default.createDirectory(
            at: kernelDir,
            withIntermediateDirectories: true
        )
    }

    /// Get kernel configuration for VM boot
    public func getKernel() async throws -> Kernel {
        if let cached = cachedKernel {
            return cached
        }

        // Determine platform
        #if arch(arm64)
        let platform = SystemPlatform.linuxArm
        let kernelFilename = "vmlinuz-arm64"
        #elseif arch(x86_64)
        let platform = SystemPlatform.linuxAmd
        let kernelFilename = "vmlinuz-x86_64"
        #else
        throw KernelError.invalidPlatform
        #endif

        let kernelPath = kernelDir.appendingPathComponent(kernelFilename)

        // Check if kernel exists
        if !FileManager.default.fileExists(atPath: kernelPath.path) {
            logger.info("Kernel not found at default location, searching system paths...")

            // Try common kernel locations
            let possiblePaths = [
                // Apple Containerization framework locations
                "/usr/share/containerization/kernel/vmlinuz",
                "/opt/homebrew/share/containerization/kernel/vmlinuz",
                "/usr/local/share/containerization/kernel/vmlinuz",

                // Kata Containers locations (if installed)
                "/opt/kata/share/kata-containers/vmlinuz.container",
                "/usr/share/kata-containers/vmlinuz.container",

                // Custom locations
                "/usr/local/share/linux-kernel/vmlinuz",

                // Homebrew Cellar paths
                "/opt/homebrew/Cellar/containerization/*/share/containerization/kernel/vmlinuz",
                "/usr/local/Cellar/containerization/*/share/containerization/kernel/vmlinuz"
            ]

            for pathPattern in possiblePaths {
                // Handle glob patterns
                if pathPattern.contains("*") {
                    // This is simplified - in production we'd want proper glob expansion
                    continue
                }

                if FileManager.default.fileExists(atPath: pathPattern) {
                    logger.info("Found kernel at \(pathPattern)")
                    let kernel = Kernel(
                        path: URL(fileURLWithPath: pathPattern),
                        platform: platform,
                        commandline: Kernel.CommandLine(
                            kernelArgs: ["console=hvc0", "tsc=reliable"],
                            initArgs: []
                        )
                    )
                    cachedKernel = kernel
                    return kernel
                }
            }

            logger.error("No Linux kernel found in any known location")
            throw KernelError.kernelNotFound
        }

        let kernel = Kernel(
            path: kernelPath,
            platform: platform,
            commandline: Kernel.CommandLine(
                kernelArgs: ["console=hvc0", "tsc=reliable"],
                initArgs: []
            )
        )

        cachedKernel = kernel
        logger.info("Kernel loaded", metadata: ["path": "\(kernelPath.path)"])

        return kernel
    }

    /// Get initfs reference for ContainerManager
    public nonisolated func getInitfsReference() -> String {
        // Use vminit:latest as specified in the plan
        return "vminit:latest"
    }

    /// Download or verify kernel is available
    public func ensureKernelAvailable() async throws {
        _ = try await getKernel()
    }

    /// Check if a kernel is available without throwing
    public func checkKernelAvailable() async -> Bool {
        do {
            _ = try await getKernel()
            return true
        } catch {
            return false
        }
    }

    /// Get helpful setup instructions
    public nonisolated func getSetupInstructions() -> String {
        return """
        Compote requires a Linux kernel to run containers.

        Quick Setup (Recommended):
        ---------------------------
        1. Install Apple's containerization framework via Homebrew:

           brew tap apple/containerization
           brew install containerization

           This will install the necessary kernel and tools.

        Manual Setup:
        -------------
        If you prefer to build from source:

        1. Clone the containerization repository:
           git clone https://github.com/apple/containerization.git
           cd containerization

        2. Build the kernel:
           cd kernel
           make

        3. Install the kernel:
           sudo mkdir -p /usr/local/share/containerization/kernel
           sudo cp build/vmlinuz /usr/local/share/containerization/kernel/

        Alternative:
        -----------
        Place a Linux kernel binary at:
        ~/Library/Application Support/compote/kernel/vmlinuz-arm64

        For more information:
        https://github.com/apple/containerization
        """
    }
}
