import XCTest
@testable import ContextPacketCore

final class ProjectDetectorTests: XCTestCase {
    var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testSwiftProjectDetection() throws {
        let packageSwift = tempDirectory.appendingPathComponent("Package.swift")
        try "// swift-tools-version: 5.9".write(to: packageSwift, atomically: true, encoding: .utf8)

        let detector = ProjectDetector()
        let metadata = detector.detect(at: tempDirectory)

        XCTAssertEqual(metadata.ecosystem, "Swift")
        XCTAssertEqual(metadata.language, "Swift")
        XCTAssertTrue(metadata.detectedConfigFiles.contains("Package.swift"))
    }

    func testNodeProjectDetection() throws {
        let packageJson = tempDirectory.appendingPathComponent("package.json")
        let packageContent = """
        {
          "name": "test-web",
          "scripts": {
            "dev": "vite",
            "build": "vite build"
          },
          "dependencies": {
            "react": "^18.2.0"
          }
        }
        """
        try packageContent.write(to: packageJson, atomically: true, encoding: .utf8)

        let detector = ProjectDetector()
        let metadata = detector.detect(at: tempDirectory)

        XCTAssertTrue(metadata.ecosystem.contains("Node"))
        XCTAssertEqual(metadata.language, "JavaScript")
        XCTAssertEqual(metadata.framework, "React")
        XCTAssertEqual(metadata.scripts["dev"], "vite")
    }

    func testRustProjectDetection() throws {
        let cargoToml = tempDirectory.appendingPathComponent("Cargo.toml")
        try "[package]\nname = \"my-crate\"".write(to: cargoToml, atomically: true, encoding: .utf8)

        let detector = ProjectDetector()
        let metadata = detector.detect(at: tempDirectory)

        XCTAssertEqual(metadata.ecosystem, "Rust")
        XCTAssertEqual(metadata.language, "Rust")
    }

    func testPythonProjectDetection() throws {
        let pyproject = tempDirectory.appendingPathComponent("pyproject.toml")
        try "[project]\nname = \"my-tool\"".write(to: pyproject, atomically: true, encoding: .utf8)

        let detector = ProjectDetector()
        let metadata = detector.detect(at: tempDirectory)

        XCTAssertEqual(metadata.ecosystem, "Python")
        XCTAssertEqual(metadata.language, "Python")
    }
}
