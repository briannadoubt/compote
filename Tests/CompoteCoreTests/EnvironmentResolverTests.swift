import XCTest
@testable import CompoteCore

final class EnvironmentResolverTests: XCTestCase {

    func testSimpleVariable() throws {
        let resolver = EnvironmentResolver(environment: ["FOO": "bar"])
        let result = resolver.resolve("Value is ${FOO}")
        XCTAssertEqual(result, "Value is bar")
    }

    func testMultipleVariables() throws {
        let resolver = EnvironmentResolver(environment: ["FOO": "bar", "BAZ": "qux"])
        let result = resolver.resolve("${FOO} and ${BAZ}")
        XCTAssertEqual(result, "bar and qux")
    }

    func testDefaultWithExisting() throws {
        let resolver = EnvironmentResolver(environment: ["FOO": "bar"])
        let result = resolver.resolve("${FOO:-default}")
        XCTAssertEqual(result, "bar")
    }

    func testDefaultWithMissing() throws {
        let resolver = EnvironmentResolver(environment: [:])
        let result = resolver.resolve("${FOO:-default}")
        XCTAssertEqual(result, "default")
    }

    func testDefaultWithSpecialChars() throws {
        let resolver = EnvironmentResolver(environment: [:])
        let result = resolver.resolve("${FOO:-/path/to/file}")
        XCTAssertEqual(result, "/path/to/file")
    }

    func testUnresolvedVariableBecomesEmpty() throws {
        let resolver = EnvironmentResolver(environment: [:])
        let result = resolver.resolve("${FOO}")
        // Without default, missing variables become empty
        XCTAssertEqual(result, "")
    }

    func testVariableNaming() throws {
        let resolver = EnvironmentResolver(environment: ["MY_VAR_123": "value"])
        let result = resolver.resolve("${MY_VAR_123}")
        XCTAssertEqual(result, "value")
    }

    func testEmptyValue() throws {
        let resolver = EnvironmentResolver(environment: ["FOO": ""])
        let result = resolver.resolve("${FOO}")
        XCTAssertEqual(result, "")
    }

    func testNoVariables() throws {
        let resolver = EnvironmentResolver(environment: [:])
        let result = resolver.resolve("plain text")
        XCTAssertEqual(result, "plain text")
    }

    func testSimpleDollarVariable() throws {
        let resolver = EnvironmentResolver(environment: ["FOO": "bar"])
        let result = resolver.resolve("Value is $FOO")
        XCTAssertEqual(result, "Value is bar")
    }
}
