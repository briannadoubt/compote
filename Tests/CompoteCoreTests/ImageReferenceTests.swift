@testable import CompoteCore
import XCTest

final class ImageReferenceTests: XCTestCase {
    func testCanonicalizesBareName() {
        XCTAssertEqual(
            ImageManager.canonicalImageReference("nginx"),
            "docker.io/library/nginx:latest"
        )
    }

    func testCanonicalizesBareNameWithTag() {
        XCTAssertEqual(
            ImageManager.canonicalImageReference("nginx:alpine"),
            "docker.io/library/nginx:alpine"
        )
    }

    func testCanonicalizesOrgImageWithTag() {
        XCTAssertEqual(
            ImageManager.canonicalImageReference("swiftlang/swift:nightly"),
            "docker.io/swiftlang/swift:nightly"
        )
    }

    func testKeepsQualifiedReference() {
        XCTAssertEqual(
            ImageManager.canonicalImageReference("ghcr.io/apple/containerization/vminit:0.13.0"),
            "ghcr.io/apple/containerization/vminit:0.13.0"
        )
    }
}
