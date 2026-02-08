import XCTest
@testable import CompoteCore

final class LogBufferTests: XCTestCase {

    func testStreamWithoutFollowReturnsBufferedLinesOnly() async throws {
        let buffer = LogBuffer()
        await buffer.append(Data("line1\nline2\n".utf8))

        var received: [String] = []
        for await line in await buffer.stream(follow: false) {
            received.append(line)
        }

        XCTAssertEqual(received, ["line1\n", "line2\n"])
    }

    func testTailReturnsOnlyLastLines() async throws {
        let buffer = LogBuffer()
        await buffer.append(Data("line1\nline2\nline3\n".utf8))

        var received: [String] = []
        for await line in await buffer.stream(tail: 2, follow: false) {
            received.append(line)
        }

        XCTAssertEqual(received, ["line2\n", "line3\n"])
    }
}
