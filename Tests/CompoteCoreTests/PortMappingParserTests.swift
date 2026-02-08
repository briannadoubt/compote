import XCTest
@testable import CompoteCore

final class PortMappingParserTests: XCTestCase {

    func testParsesTcpMappingWithoutHostIP() throws {
        let mapping = try PortMappingParser.parse("8080:80")
        XCTAssertEqual(mapping.hostIP, "0.0.0.0")
        XCTAssertEqual(mapping.hostPort, 8080)
        XCTAssertEqual(mapping.containerPort, 80)
        XCTAssertEqual(mapping.proto, "tcp")
    }

    func testParsesUdpMappingWithHostIP() throws {
        let mapping = try PortMappingParser.parse("127.0.0.1:5353:53/udp")
        XCTAssertEqual(mapping.hostIP, "127.0.0.1")
        XCTAssertEqual(mapping.hostPort, 5353)
        XCTAssertEqual(mapping.containerPort, 53)
        XCTAssertEqual(mapping.proto, "udp")
    }

    func testRejectsUnsupportedProtocol() {
        XCTAssertThrowsError(try PortMappingParser.parse("8080:80/sctp"))
    }

    func testRejectsInvalidPortValues() {
        XCTAssertThrowsError(try PortMappingParser.parse("0:80"))
        XCTAssertThrowsError(try PortMappingParser.parse("8080:70000"))
        XCTAssertThrowsError(try PortMappingParser.parse("abc:80"))
    }

    func testRejectsInvalidFormat() {
        XCTAssertThrowsError(try PortMappingParser.parse("8080"))
        XCTAssertThrowsError(try PortMappingParser.parse("1:2:3:4"))
    }
}
