import XCTest
@testable import ContextPacketCore

final class TodoScannerTests: XCTestCase {
    var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testTodoExtraction() throws {
        let codeFile = tempDirectory.appendingPathComponent("App.swift")
        let content = """
        import SwiftUI

        // TODO: Handle battery source disappearing after sleep
        struct AppView: View {
            // FIXME: Animation restarts when view mounts
            var body: some View {
                Text("Hello")
                // HACK: Quick bypass for macOS bug
            }
        }
        """
        try content.write(to: codeFile, atomically: true, encoding: .utf8)

        let scanner = TodoScanner()
        let results = scanner.scan(at: tempDirectory, changedFiles: ["App.swift"])

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].kind, "TODO")
        XCTAssertTrue(results[0].comment.contains("Handle battery source disappearing"))
        XCTAssertEqual(results[1].kind, "FIXME")
        XCTAssertTrue(results[1].comment.contains("Animation restarts"))
        XCTAssertEqual(results[2].kind, "HACK")
        XCTAssertTrue(results[2].comment.contains("Quick bypass"))
        XCTAssertTrue(results[0].isInsideChangedFile)
    }
}
