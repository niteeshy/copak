import Foundation

public struct ProjectMetadata: Codable, Sendable, Equatable {
    public var ecosystem: String
    public var language: String?
    public var framework: String?
    public var packageManager: String?
    public var applicationType: String?
    public var buildSystem: String?
    public var detectedConfigFiles: [String]
    public var scripts: [String: String]
    public var topDependencies: [String]

    public init(
        ecosystem: String = "Generic",
        language: String? = nil,
        framework: String? = nil,
        packageManager: String? = nil,
        applicationType: String? = nil,
        buildSystem: String? = nil,
        detectedConfigFiles: [String] = [],
        scripts: [String: String] = [:],
        topDependencies: [String] = []
    ) {
        self.ecosystem = ecosystem
        self.language = language
        self.framework = framework
        self.packageManager = packageManager
        self.applicationType = applicationType
        self.buildSystem = buildSystem
        self.detectedConfigFiles = detectedConfigFiles
        self.scripts = scripts
        self.topDependencies = topDependencies
    }
}
