import Foundation

/// Service configuration in compose file
public struct Service: Codable, Sendable {
    // Image and build
    public let image: String?
    public let build: BuildConfig?

    // Container configuration
    public let container_name: String?
    public let hostname: String?
    public let command: Command?
    public let entrypoint: Command?
    public let working_dir: String?
    public let user: String?

    // Environment
    public let environment: Environment?
    public let env_file: EnvFile?

    // Ports and networking
    public let ports: [String]?
    public let expose: [String]?
    public let networks: Networks?

    // Volumes and mounts
    public let volumes: [String]?
    public let tmpfs: [String]?
    public let configs: [ServiceConfigReference]?
    public let secrets: [ServiceSecretReference]?

    // Dependencies
    public let depends_on: DependsOn?

    // Health check
    public let healthcheck: HealthCheck?

    // Resources
    public let deploy: DeployConfig?

    // Restart policy
    public let restart: String?

    // Labels and profiles
    public let labels: [String: String]?
    public let profiles: [String]?

    // Logging
    public let logging: LoggingConfig?

    public init(
        image: String? = nil,
        build: BuildConfig? = nil,
        container_name: String? = nil,
        hostname: String? = nil,
        command: Command? = nil,
        entrypoint: Command? = nil,
        working_dir: String? = nil,
        user: String? = nil,
        environment: Environment? = nil,
        env_file: EnvFile? = nil,
        ports: [String]? = nil,
        expose: [String]? = nil,
        networks: Networks? = nil,
        volumes: [String]? = nil,
        tmpfs: [String]? = nil,
        configs: [ServiceConfigReference]? = nil,
        secrets: [ServiceSecretReference]? = nil,
        depends_on: DependsOn? = nil,
        healthcheck: HealthCheck? = nil,
        deploy: DeployConfig? = nil,
        restart: String? = nil,
        labels: [String: String]? = nil,
        profiles: [String]? = nil,
        logging: LoggingConfig? = nil
    ) {
        self.image = image
        self.build = build
        self.container_name = container_name
        self.hostname = hostname
        self.command = command
        self.entrypoint = entrypoint
        self.working_dir = working_dir
        self.user = user
        self.environment = environment
        self.env_file = env_file
        self.ports = ports
        self.expose = expose
        self.networks = networks
        self.volumes = volumes
        self.tmpfs = tmpfs
        self.configs = configs
        self.secrets = secrets
        self.depends_on = depends_on
        self.healthcheck = healthcheck
        self.deploy = deploy
        self.restart = restart
        self.labels = labels
        self.profiles = profiles
        self.logging = logging
    }
}

public struct ServiceConfigReferenceObject: Codable, Sendable {
    public let source: String
    public let target: String?

    public init(source: String, target: String? = nil) {
        self.source = source
        self.target = target
    }
}

public enum ServiceConfigReference: Codable, Sendable {
    case simple(String)
    case detailed(ServiceConfigReferenceObject)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let source = try? container.decode(String.self) {
            self = .simple(source)
        } else if let object = try? container.decode(ServiceConfigReferenceObject.self) {
            self = .detailed(object)
        } else {
            throw DecodingError.typeMismatch(
                ServiceConfigReference.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected string or config object"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .simple(let source):
            try container.encode(source)
        case .detailed(let object):
            try container.encode(object)
        }
    }

    public var source: String {
        switch self {
        case .simple(let source):
            return source
        case .detailed(let object):
            return object.source
        }
    }

    public var target: String? {
        switch self {
        case .simple:
            return nil
        case .detailed(let object):
            return object.target
        }
    }
}

public struct ServiceSecretReferenceObject: Codable, Sendable {
    public let source: String
    public let target: String?

    public init(source: String, target: String? = nil) {
        self.source = source
        self.target = target
    }
}

public enum ServiceSecretReference: Codable, Sendable {
    case simple(String)
    case detailed(ServiceSecretReferenceObject)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let source = try? container.decode(String.self) {
            self = .simple(source)
        } else if let object = try? container.decode(ServiceSecretReferenceObject.self) {
            self = .detailed(object)
        } else {
            throw DecodingError.typeMismatch(
                ServiceSecretReference.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected string or secret object"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .simple(let source):
            try container.encode(source)
        case .detailed(let object):
            try container.encode(object)
        }
    }

    public var source: String {
        switch self {
        case .simple(let source):
            return source
        case .detailed(let object):
            return object.source
        }
    }

    public var target: String? {
        switch self {
        case .simple:
            return nil
        case .detailed(let object):
            return object.target
        }
    }
}

/// Command can be string or array
public enum Command: Codable, Sendable {
    case string(String)
    case array([String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([String].self) {
            self = .array(array)
        } else {
            throw DecodingError.typeMismatch(
                Command.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected string or array"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let string):
            try container.encode(string)
        case .array(let array):
            try container.encode(array)
        }
    }

    public var asArray: [String] {
        switch self {
        case .string(let string):
            // Simple shell splitting
            return string.split(separator: " ").map(String.init)
        case .array(let array):
            return array
        }
    }
}

/// Environment can be dict or array
public enum Environment: Codable, Sendable {
    case dictionary([String: String])
    case array([String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: String].self) {
            self = .dictionary(dict)
        } else if let array = try? container.decode([String].self) {
            self = .array(array)
        } else {
            throw DecodingError.typeMismatch(
                Environment.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected dictionary or array"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .dictionary(let dict):
            try container.encode(dict)
        case .array(let array):
            try container.encode(array)
        }
    }

    public var asDictionary: [String: String] {
        switch self {
        case .dictionary(let dict):
            return dict
        case .array(let array):
            var dict: [String: String] = [:]
            for item in array {
                if let index = item.firstIndex(of: "=") {
                    let key = String(item[..<index])
                    let value = String(item[item.index(after: index)...])
                    dict[key] = value
                } else {
                    dict[item] = ProcessInfo.processInfo.environment[item] ?? ""
                }
            }
            return dict
        }
    }
}

/// Env file can be string or array
public enum EnvFile: Codable, Sendable {
    case single(String)
    case multiple([String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .single(string)
        } else if let array = try? container.decode([String].self) {
            self = .multiple(array)
        } else {
            throw DecodingError.typeMismatch(
                EnvFile.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected string or array"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let string):
            try container.encode(string)
        case .multiple(let array):
            try container.encode(array)
        }
    }

    public var asArray: [String] {
        switch self {
        case .single(let string):
            return [string]
        case .multiple(let array):
            return array
        }
    }
}

/// Networks can be array or dict
public enum Networks: Codable, Sendable {
    case array([String])
    case dictionary([String: NetworkConfig])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([String].self) {
            self = .array(array)
        } else if let dict = try? container.decode([String: NetworkConfig].self) {
            self = .dictionary(dict)
        } else {
            throw DecodingError.typeMismatch(
                Networks.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected array or dictionary"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .array(let array):
            try container.encode(array)
        case .dictionary(let dict):
            try container.encode(dict)
        }
    }
}

public struct NetworkConfig: Codable, Sendable {
    public let aliases: [String]?
    public let ipv4_address: String?
    public let ipv6_address: String?

    public init(aliases: [String]? = nil, ipv4_address: String? = nil, ipv6_address: String? = nil) {
        self.aliases = aliases
        self.ipv4_address = ipv4_address
        self.ipv6_address = ipv6_address
    }
}

/// Build configuration
public struct BuildConfig: Codable, Sendable {
    public let context: String?
    public let dockerfile: String?
    public let args: [String: String]?
    public let target: String?
    public let labels: [String: String]?

    public init(
        context: String? = nil,
        dockerfile: String? = nil,
        args: [String: String]? = nil,
        target: String? = nil,
        labels: [String: String]? = nil
    ) {
        self.context = context
        self.dockerfile = dockerfile
        self.args = args
        self.target = target
        self.labels = labels
    }
}

/// Depends on can be array or dict
public enum DependsOn: Codable, Sendable {
    case array([String])
    case dictionary([String: DependencyCondition])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([String].self) {
            self = .array(array)
        } else if let dict = try? container.decode([String: DependencyCondition].self) {
            self = .dictionary(dict)
        } else {
            throw DecodingError.typeMismatch(
                DependsOn.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected array or dictionary"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .array(let array):
            try container.encode(array)
        case .dictionary(let dict):
            try container.encode(dict)
        }
    }

    public var dependencies: [(String, DependencyCondition)] {
        switch self {
        case .array(let array):
            return array.map { ($0, DependencyCondition()) }
        case .dictionary(let dict):
            return dict.map { ($0.key, $0.value) }
        }
    }
}

public struct DependencyCondition: Codable, Sendable {
    public let condition: String?
    public let restart: Bool?

    public init(condition: String? = nil, restart: Bool? = nil) {
        self.condition = condition
        self.restart = restart
    }
}

/// Health check configuration
public struct HealthCheck: Codable, Sendable {
    public let test: Command?
    public let interval: String?
    public let timeout: String?
    public let retries: Int?
    public let start_period: String?
    public let disable: Bool?

    public init(
        test: Command? = nil,
        interval: String? = nil,
        timeout: String? = nil,
        retries: Int? = nil,
        start_period: String? = nil,
        disable: Bool? = nil
    ) {
        self.test = test
        self.interval = interval
        self.timeout = timeout
        self.retries = retries
        self.start_period = start_period
        self.disable = disable
    }
}

/// Deploy configuration for resources
public struct DeployConfig: Codable, Sendable {
    public let resources: ResourcesConfig?
    public let replicas: Int?
    public let restart_policy: RestartPolicy?

    public init(
        resources: ResourcesConfig? = nil,
        replicas: Int? = nil,
        restart_policy: RestartPolicy? = nil
    ) {
        self.resources = resources
        self.replicas = replicas
        self.restart_policy = restart_policy
    }
}

public struct ResourcesConfig: Codable, Sendable {
    public let limits: ResourceLimits?
    public let reservations: ResourceLimits?

    public init(limits: ResourceLimits? = nil, reservations: ResourceLimits? = nil) {
        self.limits = limits
        self.reservations = reservations
    }
}

public struct ResourceLimits: Codable, Sendable {
    public let cpus: String?
    public let memory: String?

    public init(cpus: String? = nil, memory: String? = nil) {
        self.cpus = cpus
        self.memory = memory
    }
}

public struct RestartPolicy: Codable, Sendable {
    public let condition: String?
    public let delay: String?
    public let max_attempts: Int?
    public let window: String?

    public init(
        condition: String? = nil,
        delay: String? = nil,
        max_attempts: Int? = nil,
        window: String? = nil
    ) {
        self.condition = condition
        self.delay = delay
        self.max_attempts = max_attempts
        self.window = window
    }
}

/// Logging configuration
public struct LoggingConfig: Codable, Sendable {
    public let driver: String?
    public let options: [String: String]?

    public init(driver: String? = nil, options: [String: String]? = nil) {
        self.driver = driver
        self.options = options
    }
}
