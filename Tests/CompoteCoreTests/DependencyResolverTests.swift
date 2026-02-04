import XCTest
@testable import CompoteCore

final class DependencyResolverTests: XCTestCase {

    func testSimpleChain() throws {
        let services: [String: Service] = [
            "web": Service(image: "nginx", depends_on: .array(["db"])),
            "db": Service(image: "postgres")
        ]

        let resolver = DependencyResolver()
        let batches = try resolver.resolveStartupOrder(services: services)

        // db should be in first batch, web in second
        XCTAssertEqual(batches.count, 2)
        XCTAssertEqual(batches[0], ["db"])
        XCTAssertEqual(batches[1], ["web"])
    }

    func testParallelServices() throws {
        let services: [String: Service] = [
            "web1": Service(image: "nginx"),
            "web2": Service(image: "nginx"),
            "web3": Service(image: "nginx")
        ]

        let resolver = DependencyResolver()
        let batches = try resolver.resolveStartupOrder(services: services)

        // All services should be in one batch since no dependencies
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches[0].count, 3)
        XCTAssertTrue(batches[0].contains("web1"))
        XCTAssertTrue(batches[0].contains("web2"))
        XCTAssertTrue(batches[0].contains("web3"))
    }

    func testComplexGraph() throws {
        let services: [String: Service] = [
            "frontend": Service(image: "react", depends_on: .array(["backend"])),
            "backend": Service(image: "node", depends_on: .array(["db", "cache"])),
            "db": Service(image: "postgres"),
            "cache": Service(image: "redis")
        ]

        let resolver = DependencyResolver()
        let batches = try resolver.resolveStartupOrder(services: services)

        // Batch 0: db, cache (parallel)
        // Batch 1: backend
        // Batch 2: frontend
        XCTAssertEqual(batches.count, 3)
        XCTAssertEqual(batches[0].count, 2)
        XCTAssertTrue(batches[0].contains("cache"))
        XCTAssertTrue(batches[0].contains("db"))
        XCTAssertEqual(batches[1], ["backend"])
        XCTAssertEqual(batches[2], ["frontend"])
    }

    func testCircularDependency() throws {
        let services: [String: Service] = [
            "web": Service(image: "nginx", depends_on: .array(["db"])),
            "db": Service(image: "postgres", depends_on: .array(["web"]))
        ]

        let resolver = DependencyResolver()
        XCTAssertThrowsError(try resolver.resolveStartupOrder(services: services)) { error in
            XCTAssertTrue(error is DependencyError)
        }
    }

    func testSelfDependency() throws {
        let services: [String: Service] = [
            "web": Service(image: "nginx", depends_on: .array(["web"]))
        ]

        let resolver = DependencyResolver()
        XCTAssertThrowsError(try resolver.resolveStartupOrder(services: services)) { error in
            XCTAssertTrue(error is DependencyError)
        }
    }

    func testMissingDependency() throws {
        let services: [String: Service] = [
            "web": Service(image: "nginx", depends_on: .array(["nonexistent"]))
        ]

        let resolver = DependencyResolver()
        XCTAssertThrowsError(try resolver.resolveStartupOrder(services: services)) { error in
            if case DependencyError.missingService(let name) = error {
                XCTAssertEqual(name, "nonexistent")
            } else {
                XCTFail("Expected missingService error")
            }
        }
    }

    func testDiamondPattern() throws {
        let services: [String: Service] = [
            "app": Service(image: "app", depends_on: .array(["service1", "service2"])),
            "service1": Service(image: "svc1", depends_on: .array(["db"])),
            "service2": Service(image: "svc2", depends_on: .array(["db"])),
            "db": Service(image: "postgres")
        ]

        let resolver = DependencyResolver()
        let batches = try resolver.resolveStartupOrder(services: services)

        // Batch 0: db
        // Batch 1: service1, service2 (parallel)
        // Batch 2: app
        XCTAssertEqual(batches.count, 3)
        XCTAssertEqual(batches[0], ["db"])
        XCTAssertEqual(batches[1].count, 2)
        XCTAssertTrue(batches[1].contains("service1"))
        XCTAssertTrue(batches[1].contains("service2"))
        XCTAssertEqual(batches[2], ["app"])
    }

    func testEmptyServices() throws {
        let services: [String: Service] = [:]

        let resolver = DependencyResolver()
        let batches = try resolver.resolveStartupOrder(services: services)

        XCTAssertTrue(batches.isEmpty)
    }

    func testLongChain() throws {
        let services: [String: Service] = [
            "layer5": Service(image: "app", depends_on: .array(["layer4"])),
            "layer4": Service(image: "app", depends_on: .array(["layer3"])),
            "layer3": Service(image: "app", depends_on: .array(["layer2"])),
            "layer2": Service(image: "app", depends_on: .array(["layer1"])),
            "layer1": Service(image: "app")
        ]

        let resolver = DependencyResolver()
        let batches = try resolver.resolveStartupOrder(services: services)

        XCTAssertEqual(batches.count, 5)
        XCTAssertEqual(batches[0], ["layer1"])
        XCTAssertEqual(batches[1], ["layer2"])
        XCTAssertEqual(batches[2], ["layer3"])
        XCTAssertEqual(batches[3], ["layer4"])
        XCTAssertEqual(batches[4], ["layer5"])
    }
}
