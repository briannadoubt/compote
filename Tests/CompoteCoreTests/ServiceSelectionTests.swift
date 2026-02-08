import XCTest
@testable import CompoteCore

final class ServiceSelectionTests: XCTestCase {

    func testParsesServiceSelectorWithoutReplica() throws {
        let selector = try ServiceSelector.parse("web")
        XCTAssertEqual(selector.serviceName, "web")
        XCTAssertNil(selector.replicaIndex)
    }

    func testParsesServiceSelectorWithReplica() throws {
        let selector = try ServiceSelector.parse("web#2")
        XCTAssertEqual(selector.serviceName, "web")
        XCTAssertEqual(selector.replicaIndex, 2)
    }

    func testRejectsInvalidServiceSelector() {
        XCTAssertThrowsError(try ServiceSelector.parse("web#0"))
        XCTAssertThrowsError(try ServiceSelector.parse("#2"))
        XCTAssertThrowsError(try ServiceSelector.parse(""))
    }

    func testBuildsSelectionMapWithAllAndReplicaMerges() throws {
        let selections = try ServiceSelections.parse(
            ["web#2", "api#3", "web#4", "web"],
            validServices: ["web", "api"]
        )

        XCTAssertEqual(selections.values["web"], .all)
        XCTAssertEqual(selections.values["api"], .indices([3]))
    }

    func testRejectsUnknownService() {
        XCTAssertThrowsError(
            try ServiceSelections.parse(["db#2"], validServices: ["web", "api"])
        )
    }
}
