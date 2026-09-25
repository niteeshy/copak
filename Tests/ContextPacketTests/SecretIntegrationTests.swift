import XCTest
@testable import ContextPacketCore

final class SecretIntegrationTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("secret-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testSecretsFromEverySourceCannotReachPersistedOrExportedOutput() throws {
        // Raw sensitive fixtures (synthetic, non-production)
        let openAiKey = "sk-proj-9876543210fedcba9876543210"
        let anthropicKey = "sk-ant-api03-abcdef1234567890abcdef12345678"
        let awsKey = "AKIA1234567890ABCDEF"
        let gitHubToken = "ghp_1234567890abcdefghijklmnopqrstuvwx"
        let databaseUrl = "postgres://adminuser:supersecretpass99@database.internal.net:5432/main"
        let sensitiveVar = "API_SECRET=\"shh_this_is_a_secret_value_12345\""
        let pemKeyBlock = """
        -----BEGIN RSA PRIVATE KEY-----
        MIIEowIBAAKCAQEAwSyntheticPrivateKeyBlockForIntegrationTestingPurpose
        Only1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ==
        -----END RSA PRIVATE KEY-----
        """
        let sensitiveGitRemote = "https://oauth2:token_abc1234567890@github.com/myorg/private-repo.git"

        let allRawSecrets = [
            openAiKey,
            anthropicKey,
            awsKey,
            gitHubToken,
            "supersecretpass99",
            "shh_this_is_a_secret_value_12345",
            "-----BEGIN RSA PRIVATE KEY-----",
            "token_abc1234567890"
        ]

        // 1. Session state fields entered by user
        let session = SavedProjectSession(
            repositoryPath: tempDir.path,
            currentGoal: "Deploy service using \(openAiKey)",
            completedWork: [ContextItem(text: "Configured database with \(databaseUrl)")],
            decisions: [Decision(text: "Set sensitive environment: \(sensitiveVar)", source: .user)],
            nextTasks: [TaskItem(text: "Connect Anthropic provider with \(anthropicKey)", source: .user)],
            knownProblems: [ProblemItem(text: "Private key leak risk: \(pemKeyBlock)", source: .user)],
            recentWork: [ContextItem(text: "Tested AWS connection using \(awsKey)")],
            notes: "GitHub CI runner configured with \(gitHubToken)"
        )

        // Test Persistence: Save session to disk and read back raw JSON
        let sessionStore = ProjectSessionStore(storageDirectory: tempDir)
        try sessionStore.saveSession(session)

        let sessionFile = tempDir.appendingPathComponent(sessionStore.storageKey(for: tempDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionFile.path))
        let persistedJson = try String(contentsOf: sessionFile, encoding: .utf8)

        // Verify that NO raw secrets exist in the persisted JSON file
        for secret in allRawSecrets {
            XCTAssertFalse(
                persistedJson.contains(secret),
                "Persisted JSON must not contain raw secret: \(secret)"
            )
        }

        // 2. Git metadata, diffs, and instruction files
        let rawDiffWithSecretFileAndTokens = """
        diff --git a/.env b/.env
        new file mode 100644
        --- /dev/null
        +++ b/.env
        @@ -0,0 +1,2 @@
        +API_SECRET="shh_this_is_a_secret_value_12345"
        +OPENAI_KEY=\(openAiKey)
        diff --git a/Sources/App.swift b/Sources/App.swift
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -10,1 +10,1 @@
        -let host = "localhost"
        +let host = "\(databaseUrl)"
        """

        let sanitizedDiff = SecretFilter.sanitizeDiff(rawDiffWithSecretFileAndTokens)
        XCTAssertFalse(sanitizedDiff.contains(".env"))
        XCTAssertFalse(sanitizedDiff.contains("shh_this_is_a_secret_value_12345"))
        XCTAssertFalse(sanitizedDiff.contains(openAiKey))
        XCTAssertFalse(sanitizedDiff.contains("supersecretpass99"))

        let project = ProjectContext(
            name: "SecureProject",
            repositoryPath: tempDir.path,
            ecosystem: "Swift",
            remoteURL: sensitiveGitRemote
        )

        let state = CanonicalRepositoryState(
            branch: "feature/auth",
            headCommit: "9876abc",
            isClean: false,
            modifiedFiles: SecretFilter.filterPaths([".env", "id_rsa", "Sources/App.swift"]),
            stagedFiles: SecretFilter.filterPaths([".env.local", "Sources/Config.swift"]),
            untrackedFiles: SecretFilter.filterPaths(["credentials.json", "README.md"]),
            diffSummary: DiffSummary(
                filesChanged: 1,
                additions: 10,
                deletions: 2,
                stagedAdditions: 10,
                stagedDeletions: 2,
                stagedFilesCount: 1,
                unstagedAdditions: 0,
                unstagedDeletions: 0,
                unstagedFilesCount: 0,
                files: [FileDelta(path: "Sources/App.swift", additions: 10, deletions: 2, isStaged: true)],
                rawDiffSnippet: sanitizedDiff,
                isTruncated: false
            ),
            refreshedAt: Date(),
            isStale: false,
            stalenessReason: nil
        )

        let handoff = Handoff(
            project: project,
            currentGoal: session.currentGoal,
            completedWork: session.completedWork,
            currentState: state,
            importantFiles: SecretFilter.filterPaths(["Sources/App.swift", ".env"]).map { ImportantFile(path: $0) },
            decisions: session.decisions,
            nextTasks: session.nextTasks,
            knownProblems: session.knownProblems,
            recentWork: session.recentWork,
            recentCommits: [
                Commit(
                    hash: "9876abc",
                    shortHash: "9876abc",
                    author: "Alice",
                    date: "2026-09-25",
                    subject: SecretFilter.sanitizeText("Fix auth with token: \(gitHubToken)")
                )
            ],
            detectedInstructions: [
                InstructionFile(
                    path: "AGENTS.md",
                    scope: "Repository-wide instructions",
                    content: SecretFilter.sanitizeText("Instructions with key: \(anthropicKey) and remote \(sensitiveGitRemote)"),
                    isTruncated: false
                )
            ],
            todos: [TodoItem(file: "Sources/App.swift", line: 12, kind: "TODO", comment: SecretFilter.sanitizeText("remove \(awsKey)"))],
            notes: session.notes
        )

        // 3. Test Markdown and All Provider Exporters
        let exporters: [any ContextExporter] = [
            GenericExporter(),
            ClaudeExporter(),
            CursorExporter(),
            CodexExporter()
        ]

        for exporter in exporters {
            for mode in [TokenBudgetMode.compact, TokenBudgetMode.standard, TokenBudgetMode.comprehensive] {
                let output = exporter.export(handoff: handoff, mode: mode)
                let finalSanitized = SecretFilter.sanitizeText(output)

                for secret in allRawSecrets {
                    XCTAssertFalse(
                        output.contains(secret),
                        "\(exporter.providerName) in mode \(mode.rawValue) must not contain raw secret: \(secret)"
                    )
                    XCTAssertFalse(
                        finalSanitized.contains(secret),
                        "Sanitized final output for \(exporter.providerName) must not contain raw secret: \(secret)"
                    )
                }

                // Verify secret file paths are excluded from file lists and diffs
                XCTAssertFalse(output.contains("diff --git a/.env"))
                XCTAssertFalse(output.contains("id_rsa"))
                XCTAssertFalse(output.contains("credentials.json"))
            }
        }
    }
}
