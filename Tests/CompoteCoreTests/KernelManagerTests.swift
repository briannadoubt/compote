@testable import CompoteCore
import XCTest

final class KernelManagerTests: XCTestCase {
    func testLatestVminitReferenceReturnsHighestVersion() {
        let refs = [
            "docker.io/library/nginx:latest",
            "ghcr.io/apple/containerization/vminit:0.12.1",
            "ghcr.io/apple/containerization/vminit:0.13.0",
            "ghcr.io/apple/containerization/vminit:0.9.9"
        ]

        let selected = KernelManager.latestVminitReference(from: refs)
        XCTAssertEqual(selected, "ghcr.io/apple/containerization/vminit:0.13.0")
    }

    func testLatestVminitReferenceIgnoresInvalidTags() {
        let refs = [
            "ghcr.io/apple/containerization/vminit:latest",
            "ghcr.io/apple/containerization/vminit:preview",
            "docker.io/library/alpine:3.20"
        ]

        let selected = KernelManager.latestVminitReference(from: refs)
        XCTAssertNil(selected)
    }
}
