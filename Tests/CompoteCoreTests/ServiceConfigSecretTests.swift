import XCTest
@testable import CompoteCore

final class ServiceConfigSecretTests: XCTestCase {
    func testParsesStringAndObjectConfigSecretReferences() throws {
        let yaml = """
        version: "3.9"
        services:
          app:
            image: nginx:latest
            configs:
              - app_config
              - source: env_config
                target: /etc/env.conf
            secrets:
              - app_secret
              - source: api_secret
                target: /run/secrets/api_token
        configs:
          app_config:
            file: ./config/app.conf
          env_config:
            file: ./config/env.conf
        secrets:
          app_secret:
            file: ./secrets/app.txt
          api_secret:
            file: ./secrets/api.txt
        """

        let compose = try ComposeFileParser().parse(yaml: yaml)
        guard let service = compose.services["app"] else {
            XCTFail("Expected service app")
            return
        }

        XCTAssertEqual(service.configs?.count, 2)
        XCTAssertEqual(service.configs?.first?.source, "app_config")
        XCTAssertNil(service.configs?.first?.target)
        XCTAssertEqual(service.configs?.last?.source, "env_config")
        XCTAssertEqual(service.configs?.last?.target, "/etc/env.conf")

        XCTAssertEqual(service.secrets?.count, 2)
        XCTAssertEqual(service.secrets?.first?.source, "app_secret")
        XCTAssertNil(service.secrets?.first?.target)
        XCTAssertEqual(service.secrets?.last?.source, "api_secret")
        XCTAssertEqual(service.secrets?.last?.target, "/run/secrets/api_token")
    }
}
