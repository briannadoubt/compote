import Foundation
import Containerization

/// A thread-safe log buffer that collects output and can be streamed
public actor LogBuffer {
    private var lines: [String] = []
    private var continuations: [AsyncStream<String>.Continuation] = []
    private var isClosed = false

    public init() {}

    public func append(_ data: Data) {
        guard !isClosed else { return }

        if let string = String(data: data, encoding: .utf8) {
            // Split by lines but preserve partial lines
            let chunks = string.components(separatedBy: "\n")
            for (index, chunk) in chunks.enumerated() {
                if index < chunks.count - 1 {
                    // Complete line
                    let line = chunk + "\n"
                    lines.append(line)
                    // Yield to all active continuations
                    for continuation in continuations {
                        continuation.yield(line)
                    }
                } else if !chunk.isEmpty {
                    // Partial line (no newline at end)
                    lines.append(chunk)
                    for continuation in continuations {
                        continuation.yield(chunk)
                    }
                }
            }
        }
    }

    public func close() {
        isClosed = true
        for continuation in continuations {
            continuation.finish()
        }
        continuations.removeAll()
    }

    public func stream() -> AsyncStream<String> {
        return AsyncStream { continuation in
            Task {
                // First, yield all existing lines
                let existingLines = await self.getLines()
                for line in existingLines {
                    continuation.yield(line)
                }

                // If already closed, finish immediately
                let closed = await self.isClosed
                if closed {
                    continuation.finish()
                } else {
                    // Otherwise, register for future lines
                    await self.registerContinuation(continuation)
                }
            }
        }
    }

    private func getLines() -> [String] {
        return lines
    }

    private func registerContinuation(_ continuation: AsyncStream<String>.Continuation) {
        guard !isClosed else {
            continuation.finish()
            return
        }
        continuations.append(continuation)
    }
}

/// A Writer that writes to a LogBuffer
public final class BufferedWriter: Writer, @unchecked Sendable {
    private let buffer: LogBuffer

    public init(buffer: LogBuffer) {
        self.buffer = buffer
    }

    public func write(_ data: Data) throws {
        Task {
            await buffer.append(data)
        }
    }

    public func close() throws {
        Task {
            await buffer.close()
        }
    }
}
