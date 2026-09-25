import XCTest
@testable import ContextPacketCore

final class EndToEndRepositoryVerificationTests: XCTestCase {
    var tempRepoURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRepoURL = FileManager.default.temporaryDirectory.appendingPathComponent("e2e_repo_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRepoURL, withIntermediateDirectories: true)

        let runner = GitCommandRunner()
        let exp = expectation(description: "git init")
        Task {
            _ = try? await runner.run(arguments: ["init", "-b", "main"], in: self.tempRepoURL)
            _ = try? await runner.run(arguments: ["config", "user.name", "ContextPacket Tester"], in: self.tempRepoURL)
            _ = try? await runner.run(arguments: ["config", "user.email", "tester@contextpacket.local"], in: self.tempRepoURL)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)
    }

    override func tearDownWithError() throws {
        if let tempRepoURL = tempRepoURL, FileManager.default.fileExists(atPath: tempRepoURL.path) {
            try? FileManager.default.removeItem(at: tempRepoURL)
        }
        try super.tearDownWithError()
    }

    func testCompleteEndToEndHandoffPipelineWithGitAndSecrets() async throws {
        let runner = GitCommandRunner()

        // 1. Setup instruction files
        // Root AGENTS.md
        let rootAgents = tempRepoURL.appendingPathComponent("AGENTS.md")
        try "Standard project rules. Follow clean architecture.".write(to: rootAgents, atomically: true, encoding: .utf8)

        // .cursor/rules/network.mdc
        let cursorDir = tempRepoURL.appendingPathComponent(".cursor/rules")
        try FileManager.default.createDirectory(at: cursorDir, withIntermediateDirectories: true)
        let cursorRule = cursorDir.appendingPathComponent("network.mdc")
        try "Always use async/await for network requests.".write(to: cursorRule, atomically: true, encoding: .utf8)

        // Nested packages/shared/AGENTS.md
        let nestedDir = tempRepoURL.appendingPathComponent("packages/shared")
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        let nestedAgents = nestedDir.appendingPathComponent("AGENTS.md")
        try "Shared module conventions.".write(to: nestedAgents, atomically: true, encoding: .utf8)

        // 2. Setup initial committed code
        let sourcesDir = tempRepoURL.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        let existingFile = sourcesDir.appendingPathComponent("App.swift")
        try "struct App {\n    let version = 1\n}\n".write(to: existingFile, atomically: true, encoding: .utf8)

        _ = try await runner.run(arguments: ["add", "."], in: tempRepoURL)
        // Commit containing a synthetic secret token in subject
        _ = try await runner.run(arguments: ["commit", "-m", "Initial commit with token sk-proj-supersecret12345678901234"], in: tempRepoURL)

        // 3. Create staged, unstaged, untracked, and secret-like files
        // Staged file
        let stagedFile = sourcesDir.appendingPathComponent("StagedModel.swift")
        try "struct StagedModel {}\n".write(to: stagedFile, atomically: true, encoding: .utf8)
        _ = try await runner.run(arguments: ["add", "Sources/StagedModel.swift"], in: tempRepoURL)

        // Unstaged modification
        try "struct App {\n    let version = 2\n    let flag = true\n}\n".write(to: existingFile, atomically: true, encoding: .utf8)

        // Untracked normal file
        let untrackedFile = tempRepoURL.appendingPathComponent("Notes.txt")
        try "Developer scratchpad note.\n".write(to: untrackedFile, atomically: true, encoding: .utf8)

        // Secret-looking files (.env, credentials.json, id_rsa)
        let envFile = tempRepoURL.appendingPathComponent(".env")
        try "API_KEY=\"sk-proj-9876543210fedcba9876543210\"\nDATABASE_URL=\"postgres://admin:pass12345@db.host:5432/prod\"\n".write(to: envFile, atomically: true, encoding: .utf8)

        let credsFile = tempRepoURL.appendingPathComponent("credentials.json")
        try "{\"aws_key\": \"AKIA1234567890EXAMPLE\"}".write(to: credsFile, atomically: true, encoding: .utf8)

        let rsaFile = tempRepoURL.appendingPathComponent("id_rsa")
        try "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA0mock\n-----END RSA PRIVATE KEY-----\n".write(to: rsaFile, atomically: true, encoding: .utf8)

        // 4. Run RepositoryAnalyzer
        let analyzer = RepositoryAnalyzer()
        let snapshot = try await analyzer.analyze(repositoryURL: tempRepoURL)

        // Verification 3: Verify branch, HEAD, modified, staged, untracked
        XCTAssertEqual(snapshot.branch, "main")
        XCTAssertNotNil(snapshot.headCommitHash)
        XCTAssertTrue(snapshot.stagedFiles.contains { $0.path.contains("StagedModel.swift") })
        XCTAssertTrue(snapshot.modifiedFiles.contains { $0.path.contains("App.swift") })
        XCTAssertTrue(snapshot.untrackedFiles.contains { $0.path.contains("Notes.txt") })

        // Verification 7: Secrets CANNOT appear in snapshot file lists
        for secretPath in [".env", "credentials.json", "id_rsa"] {
            XCTAssertFalse(snapshot.untrackedFiles.contains { $0.path.contains(secretPath) }, "Secret file \(secretPath) must not appear in untracked files")
            XCTAssertFalse(snapshot.modifiedFiles.contains { $0.path.contains(secretPath) }, "Secret file \(secretPath) must not appear in modified files")
            XCTAssertFalse(snapshot.stagedFiles.contains { $0.path.contains(secretPath) }, "Secret file \(secretPath) must not appear in staged files")
        }

        // Verify commit secret sanitization
        XCTAssertFalse(snapshot.recentCommits.first?.subject.contains("sk-proj-supersecret12345678901234") == true)
        XCTAssertTrue(snapshot.recentCommits.first?.subject.contains("[REDACTED_API_KEY]") == true)

        // Verification 5: Verify root, nested, and directory-based instruction files
        XCTAssertGreaterThanOrEqual(snapshot.detectedInstructionFiles.count, 3)
        XCTAssertTrue(snapshot.detectedInstructionFiles.contains { $0.path == "AGENTS.md" && $0.scope == "root" })
        XCTAssertTrue(snapshot.detectedInstructionFiles.contains { $0.path == ".cursor/rules/network.mdc" && $0.scope == "cursor-rule: network" })
        XCTAssertTrue(snapshot.detectedInstructionFiles.contains { $0.path == "packages/shared/AGENTS.md" && $0.scope == "packages/shared" })

        // 5. Test User-entered Session state & Persistence
        let sessionStore = ProjectSessionStore(storageDirectory: tempRepoURL)
        let rawSession = SavedProjectSession(
            repositoryPath: tempRepoURL.path,
            currentGoal: "Ship v2 with sk-ant-api03-abcdef1234567890abcdef12345678",
            completedWork: [ContextItem(text: "Database configured: postgres://user:secretpass99@host:5432/db")],
            decisions: [Decision(text: "Private key in vault: -----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----", source: .user)],
            nextTasks: [TaskItem(text: "Connect to AWS: AKIAIOSFODNN7EXAMPLE", source: .user)],
            knownProblems: [ProblemItem(text: "GitHub webhook token failed: ghp_1234567890abcdefghijklmnopqrstuvwx", source: .user)],
            recentWork: [ContextItem(text: "Assigned secret VAR: TOKEN=\"secret_token_12345\"")],
            notes: "Notes with bearer Bearer my_secret_token_value_longer_than_20"
        )
        try sessionStore.saveSession(rawSession)

        // Read session JSON back from disk
        let sessionKey = sessionStore.storageKey(for: tempRepoURL.path)
        let sessionPath = tempRepoURL.appendingPathComponent(sessionKey)
        let savedJson = try String(contentsOf: sessionPath, encoding: .utf8)

        // Prove that secrets entered by user into every field cannot reach persisted JSON
        XCTAssertFalse(savedJson.contains("sk-ant-api03-abcdef1234567890abcdef12345678"))
        XCTAssertFalse(savedJson.contains("secretpass99"))
        XCTAssertFalse(savedJson.contains("AKIAIOSFODNN7EXAMPLE"))
        XCTAssertFalse(savedJson.contains("ghp_1234567890abcdefghijklmnopqrstuvwx"))
        XCTAssertFalse(savedJson.contains("secret_token_12345"))
        XCTAssertFalse(savedJson.contains("-----BEGIN PRIVATE KEY-----"))

        // 6. Verification 4: Test All Three Budget Modes
        let canonicalState = CanonicalRepositoryState(
            branch: snapshot.branch ?? "main",
            headCommit: snapshot.headCommitHash,
            isClean: false,
            modifiedFiles: snapshot.modifiedFiles.map { $0.path },
            stagedFiles: snapshot.stagedFiles.map { $0.path },
            untrackedFiles: snapshot.untrackedFiles.map { $0.path },
            diffSummary: snapshot.diffSummary,
            refreshedAt: snapshot.refreshedAt,
            isStale: false,
            stalenessReason: nil
        )

        let loadedSanitizedSession = sessionStore.loadSession(for: tempRepoURL.path)
        let project = ProjectContext(
            name: snapshot.name,
            repositoryPath: snapshot.path.path,
            ecosystem: snapshot.projectMetadata.ecosystem,
            remoteURL: snapshot.remoteURL
        )

        let handoff = Handoff(
            project: project,
            currentGoal: loadedSanitizedSession.currentGoal,
            completedWork: loadedSanitizedSession.completedWork,
            currentState: canonicalState,
            importantFiles: [],
            decisions: loadedSanitizedSession.decisions,
            nextTasks: loadedSanitizedSession.nextTasks,
            knownProblems: loadedSanitizedSession.knownProblems,
            recentWork: loadedSanitizedSession.recentWork,
            recentCommits: snapshot.recentCommits,
            detectedInstructions: snapshot.detectedInstructionFiles,
            todos: snapshot.todos,
            notes: loadedSanitizedSession.notes
        )

        let builder = MarkdownHandoffBuilder()
        let compactPacket = builder.buildContent(handoff: handoff, mode: .compact)
        let standardPacket = builder.buildContent(handoff: handoff, mode: .standard)
        let compPacket = builder.buildContent(handoff: handoff, mode: .comprehensive)

        // Compact: references only
        XCTAssertTrue(compactPacket.contains("- AGENTS.md (scope: root)"))
        XCTAssertFalse(compactPacket.contains("```diff"))

        // Standard: bounded content
        XCTAssertTrue(standardPacket.contains("### AGENTS.md"))

        // Comprehensive: includes bounded sanitized diff excerpt
        XCTAssertTrue(compPacket.contains("## GIT DIFF EXCERPT"))
        XCTAssertTrue(compPacket.contains("StagedModel.swift"))
        // But never secret files
        XCTAssertFalse(compPacket.contains(".env"))
        XCTAssertFalse(compPacket.contains("id_rsa"))
        XCTAssertFalse(compPacket.contains("credentials.json"))

        // 7. Verification 6 & 7: Test All Exporters, Manual Preview Edits, and Clipboard / Export Sanitization
        let exporters: [any ContextExporter] = [
            GenericExporter(),
            ClaudeExporter(),
            CursorExporter(),
            CodexExporter()
        ]

        for exporter in exporters {
            let exportedText = exporter.export(handoff: handoff, mode: .standard)
            XCTAssertTrue(exportedText.contains("Snapshot captured:"), "Must indicate when snapshot was last refreshed")
            XCTAssertTrue(exportedText.contains("## CURRENT GOAL"))
            XCTAssertTrue(exportedText.contains("## NEXT TASK"))

            // Simulate user making manual edits in preview text
            let editedPreviewText = exportedText + "\n\n## Developer Manual Note\nDon't forget token sk-proj-111122223333444455556666"

            // Pre-output sanitization before copy/save
            let finalOutput = SecretFilter.sanitizeText(editedPreviewText)
            XCTAssertFalse(finalOutput.contains("sk-proj-111122223333444455556666"), "Secret entered in preview must be sanitized before output")
            XCTAssertTrue(finalOutput.contains("[REDACTED_API_KEY]"))
            XCTAssertTrue(finalOutput.contains("## Developer Manual Note"), "User manual edits in preview must be preserved")

            // Write to context.md
            let contextMdURL = tempRepoURL.appendingPathComponent("context.md")
            try finalOutput.write(to: contextMdURL, atomically: true, encoding: .utf8)
            let writtenContextMd = try String(contentsOf: contextMdURL, encoding: .utf8)
            XCTAssertFalse(writtenContextMd.contains("sk-proj-111122223333444455556666"))
            XCTAssertTrue(writtenContextMd.contains("## Developer Manual Note"))
        }
    }
}
