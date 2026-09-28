import XCTest
@testable import ContextPacketCore

final class ProjectSessionStoreMigrationTests: XCTestCase {
    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let temp = tempDirectory {
            try? FileManager.default.removeItem(at: temp)
        }
        super.tearDown()
    }

    func testLegacySessionWithSyntheticSecretsIsSanitizedOnLoadAndRewrittenAtomically() throws {
        let store = ProjectSessionStore(storageDirectory: tempDirectory)
        let repoPath = "/Users/dev/my-project"

        // Create a raw legacy JSON file directly on disk containing synthetic secrets
        let legacyJson = """
        {
          "repositoryPath": "\(repoPath)",
          "currentGoal": "Fix bug using OPENAI_API_KEY=\\"sk-proj-legacysecret1234567890\\"",
          "completedWork": [
            {
              "text": "Auth service configured with AWS_SECRET=\\"AKIAIOSFODNN7EXAMPLE\\"",
              "source": "User"
            }
          ],
          "decisions": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "text": "Decision: use PASSWORD=\\"correct horse battery staple\\"",
              "source": "User"
            }
          ],
          "nextTasks": [
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "text": "Deploy with token: ghp_1234567890abcdefghijklmnopqrstuvwx",
              "source": "User"
            }
          ],
          "knownProblems": [
            {
              "id": "33333333-3333-3333-3333-333333333333",
              "text": "DB fails with url https://user:secretpass123@db.internal:5432/app",
              "source": "User"
            }
          ],
          "recentWork": [
            {
              "text": "Tested endpoint with Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.legacySecretSignature",
              "source": "User"
            }
          ],
          "notes": "Remember: API_SECRET='quoted secret with spaces'",
          "preferredExportTarget": "claude",
          "preferredBudgetMode": "standard",
          "pinnedFiles": [
            "src/main.swift",
            ".env",
            "secrets.json"
          ]
        }
        """

        let key = store.storageKey(for: repoPath)
        let fileURL = tempDirectory.appendingPathComponent(key)
        try legacyJson.data(using: .utf8)?.write(to: fileURL)

        // Verify the file on disk currently has secrets
        let diskRawBefore = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(diskRawBefore.contains("sk-proj-legacysecret1234567890"))
        XCTAssertTrue(diskRawBefore.contains("correct horse battery staple"))
        XCTAssertTrue(diskRawBefore.contains(".env"))

        // Load the session through the store
        let loaded = store.loadSession(for: repoPath)

        // 1. Never exposes legacy raw secrets in the UI
        XCTAssertFalse(loaded.currentGoal.contains("sk-proj-legacysecret1234567890"))
        XCTAssertFalse(loaded.decisions[0].text.contains("correct horse battery staple"))
        XCTAssertFalse(loaded.nextTasks[0].text.contains("ghp_"))
        XCTAssertFalse(loaded.knownProblems[0].text.contains("secretpass123"))
        XCTAssertFalse(loaded.recentWork[0].text.contains("legacySecretSignature"))
        XCTAssertFalse(loaded.notes?.contains("quoted secret with spaces") ?? false)
        XCTAssertFalse(loaded.pinnedFiles.contains(".env"))
        XCTAssertFalse(loaded.pinnedFiles.contains("secrets.json"))

        // 2. Preserves non-sensitive context
        XCTAssertTrue(loaded.currentGoal.contains("Fix bug using OPENAI_API_KEY="))
        XCTAssertTrue(loaded.decisions[0].text.contains("Decision: use PASSWORD="))
        XCTAssertTrue(loaded.pinnedFiles.contains("src/main.swift"))
        XCTAssertEqual(loaded.preferredExportTarget, "claude")
        XCTAssertEqual(loaded.preferredBudgetMode, .standard)

        // 3. Rewrites migrated sessions atomically to disk
        let diskRawAfter = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(diskRawAfter.contains("sk-proj-legacysecret1234567890"))
        XCTAssertFalse(diskRawAfter.contains("correct horse battery staple"))
        XCTAssertFalse(diskRawAfter.contains("secretpass123"))
        XCTAssertFalse(diskRawAfter.contains(".env"))
        XCTAssertTrue(diskRawAfter.contains("[REDACTED_SECRET]"))
    }

    func testDirectoryMigrationFromContextPacketToCopakSanitizesFiles() throws {
        let legacyDir = tempDirectory.appendingPathComponent("ContextPacket/sessions", isDirectory: true)
        let copakDir = tempDirectory.appendingPathComponent("Copak/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)

        let legacyFile = legacyDir.appendingPathComponent("test-session.json")
        let legacyContent = """
        {
          "repositoryPath": "/test/repo",
          "currentGoal": "API_KEY=\\"secret123\\""
        }
        """
        try legacyContent.write(to: legacyFile, atomically: true, encoding: .utf8)

        let store = ProjectSessionStore(storageDirectory: copakDir)
        store.migrateSessions(from: legacyDir, to: copakDir)

        let migratedFile = copakDir.appendingPathComponent("test-session.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: migratedFile.path))
        let content = try String(contentsOf: migratedFile, encoding: .utf8)
        XCTAssertFalse(content.contains("secret123"))
        XCTAssertTrue(content.contains("[REDACTED_SECRET]"))
    }
}
