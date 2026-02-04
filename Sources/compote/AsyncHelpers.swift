import Foundation

/// Helper to run async code from synchronous context
func runAsyncTask<T>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
    let resultBox = ResultBox<T>()

    Task {
        do {
            let value = try await operation()
            resultBox.set(.success(value))
        } catch {
            resultBox.set(.failure(error))
        }
    }

    // Wait for result using RunLoop
    while !resultBox.hasResult {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }

    return try resultBox.get()
}

/// Thread-safe box for storing async operation results
/// NSLock is used only in synchronous methods, which is safe
final class ResultBox<T>: @unchecked Sendable {
    private var result: Result<T, Error>?
    private let lock = NSLock()

    var hasResult: Bool {
        lock.lock()
        defer { lock.unlock() }
        return result != nil
    }

    func set(_ value: Result<T, Error>) {
        lock.lock()
        defer { lock.unlock() }
        result = value
    }

    func get() throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard let result = result else {
            fatalError("No result available")
        }
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}
