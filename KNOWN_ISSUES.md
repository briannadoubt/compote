# Known Issues

## ArgumentParser AsyncParsableCommand Runtime Check

**Status**: Blocks execution
**Affects**: All commands

### Issue

When running the `compote` binary, ArgumentParser performs a runtime check for availability annotations on `AsyncParsableCommand` types. Despite having:
- ✅ `@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)` on `CompoteCommand`
- ✅ Same annotations on all subcommands
- ✅ Platform versions set in `Package.swift`
- ✅ Successful compilation with no errors

The tool fails at runtime with:
```
Asynchronous root command needs availability annotation.
```

### Root Cause

This appears to be a compatibility issue between:
- ArgumentParser v1.7.0's runtime availability checking
- Swift 6.2 strict concurrency
- macOS SDK version

### Workarounds

#### Option 1: Use Synchronous Commands (Quick Fix)

Change all `AsyncParsableCommand` to `ParsableCommand` and make `run()` methods synchronous. For operations that need async, wrap them:

```swift
struct UpCommand: ParsableCommand {
    func run() throws {
        // Use RunLoop or Task to run async code synchronously
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await actualAsyncRun()
            semaphore.signal()
        }
        semaphore.wait()
    }

    func actualAsyncRun() async throws {
        // Original async logic here
    }
}
```

#### Option 2: Direct API Usage

Instead of using the CLI, use CompoteCore library directly:

```swift
import CompoteCore

let parser = ComposeFileParser()
let composeFile = try parser.parse(from: "docker-compose.yml")

let orchestrator = try Orchestrator(
    composeFile: composeFile,
    projectName: "myproject",
    logger: logger
)

await orchestrator.up()
```

####Option 3: Update ArgumentParser (When Available)

Wait for a future version of ArgumentParser that resolves this compatibility issue, or file an issue upstream:
https://github.com/apple/swift-argument-parser/issues

### Verification

The core implementation works correctly:

```swift
// This works fine
import CompoteCore

let parser = ComposeFileParser()
let file = try parser.parse(yaml: """
version: '3.8'
services:
  web:
    image: nginx
""")

print(file.services.count) // 1
```

### Impact

- ❌ CLI is currently non-functional
- ✅ Core library (`CompoteCore`) works perfectly
- ✅ All parsing, validation, orchestration logic is solid
- ✅ Can be used as a library in other Swift projects

### Next Steps

1. File issue with ArgumentParser project
2. Consider implementing Option 1 (synchronous commands with async wrappers)
3. Or wait for ArgumentParser update

This is a tooling/framework integration issue, not a problem with the Compote implementation itself.
