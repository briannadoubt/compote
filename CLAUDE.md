# Compote

A docker-compose compatible tool for macOS that uses Apple's Containerization framework to run Linux containers in lightweight VMs.

## Critical Behaviors

### Container Runtime
- Uses Apple's Virtualization framework for VM management
- Requires Linux kernel (auto-installed via Homebrew dependency)
- ContainerManager handles image pulling and VM lifecycle
- Supports ARM64 (Apple Silicon) and x86_64 (Intel)

### Networking
- Uses vmnet for networking on macOS 26+ (Sequoia)
- Falls back gracefully on older macOS versions (no networking)
- Automatic IP allocation and DNS configuration

### Volume Management
- Named volumes persist in `~/Library/Application Support/compote/volumes/`
- Bind mounts support relative paths, absolute paths, and ~ expansion
- State persists across terminal sessions via JSON state files

### State Persistence
- All container, network, and volume state saved to disk
- `compote down --volumes` works across sessions
- State files in `~/Library/Application Support/compote/state/`

### Distribution
- Distributed via Homebrew tap: `brew tap briannadoubt/tap`
- Kernel dependency handled automatically by Homebrew
- Formula in separate `homebrew-tap` repository

## Swift
- Executable Swift Package
- Swift 6.2 with strict concurrency enabled
- Actor-based architecture for thread safety
- All models are `Sendable`

## Dependencies
- Apple Containerization framework (provides kernel)
- Swift ArgumentParser for CLI
- Yams for YAML parsing
- Swift Log for logging

