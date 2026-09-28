import XCTest
@testable import ContextPacketCore

final class SecretFilterTests: XCTestCase {
    func testSecretFilenamesAreDetected() {
        XCTAssertTrue(SecretFilter.isSecretFile(path: ".env"))
        XCTAssertTrue(SecretFilter.isSecretFile(path: ".env.local"))
        XCTAssertTrue(SecretFilter.isSecretFile(path: ".env.production"))
        XCTAssertTrue(SecretFilter.isSecretFile(path: "server.pem"))
        XCTAssertTrue(SecretFilter.isSecretFile(path: "id_rsa"))
        XCTAssertTrue(SecretFilter.isSecretFile(path: "id_ed25519"))
        XCTAssertTrue(SecretFilter.isSecretFile(path: "credentials.json"))
        XCTAssertTrue(SecretFilter.isSecretFile(path: "config/secrets.p12"))
        XCTAssertTrue(SecretFilter.isSecretFile(path: "app.key"))
    }

    func testNonSecretFilesPass() {
        XCTAssertFalse(SecretFilter.isSecretFile(path: "Package.swift"))
        XCTAssertFalse(SecretFilter.isSecretFile(path: "README.md"))
        XCTAssertFalse(SecretFilter.isSecretFile(path: "src/App.tsx"))
        XCTAssertFalse(SecretFilter.isSecretFile(path: "main.py"))
    }

    func testFilteringPathList() {
        let paths = [
            "src/index.ts",
            ".env",
            "README.md",
            "id_rsa",
            "package.json",
            "credentials.xml"
        ]
        let filtered = SecretFilter.filterPaths(paths)
        XCTAssertEqual(filtered, ["src/index.ts", "README.md", "package.json"])
    }

    func testSanitizeTextRedactsSensitiveAssignmentsAndRetainsContext() {
        let input = """
        let port = 8080
        OPENAI_API_KEY = "sk-proj-secret123"
        let host = "localhost"
        AWS_SECRET: "my-aws-secret"
        """
        let sanitized = SecretFilter.sanitizeText(input)
        XCTAssertFalse(sanitized.contains("sk-proj-secret123"))
        XCTAssertFalse(sanitized.contains("my-aws-secret"))
        XCTAssertTrue(sanitized.contains("OPENAI_API_KEY = \"[REDACTED_SECRET]\""))
        XCTAssertTrue(sanitized.contains("AWS_SECRET: \"[REDACTED_SECRET]\""))
        XCTAssertTrue(sanitized.contains("let port = 8080"))
    }

    func testSanitizeTextRedactsUrlCredentials() {
        let input = "git remote add origin https://admin:superSecret123@github.com/myorg/myrepo.git"
        let sanitized = SecretFilter.sanitizeText(input)
        XCTAssertFalse(sanitized.contains("superSecret123"))
        XCTAssertTrue(sanitized.contains("https://admin:[REDACTED_CREDENTIAL]@github.com/myorg/myrepo.git"))
    }

    func testSanitizeTextRedactsPemPrivateKeyBlocks() {
        let input = """
        Here is the server private key:
        -----BEGIN RSA PRIVATE KEY-----
        MIIEowIBAAKCAQEA0Y1+examplePrivateDataKey1234567890
        abcdefghijklmnopqrstuvwxyz
        -----END RSA PRIVATE KEY-----
        Next instruction line.
        """
        let sanitized = SecretFilter.sanitizeText(input)
        XCTAssertFalse(sanitized.contains("examplePrivateDataKey1234567890"))
        XCTAssertTrue(sanitized.contains("[REDACTED_PRIVATE_KEY_BLOCK]"))
        XCTAssertTrue(sanitized.contains("Next instruction line."))
    }

    func testSanitizeTextRedactsCommonApiKeys() {
        let input = """
        OpenAI: sk-proj-1234567890abcdef12345678
        Anthropic: sk-ant-1234567890abcdef12345678
        AWS: AKIAIOSFODNN7EXAMPLE
        GitHub: ghp_1234567890abcdefghijklmnopqrstuvwx
        """
        let sanitized = SecretFilter.sanitizeText(input)
        XCTAssertFalse(sanitized.contains("sk-proj-1234567890abcdef12345678"))
        XCTAssertFalse(sanitized.contains("sk-ant-1234567890abcdef12345678"))
        XCTAssertFalse(sanitized.contains("AKIAIOSFODNN7EXAMPLE"))
        XCTAssertFalse(sanitized.contains("ghp_1234567890abcdefghijklmnopqrstuvwx"))
        XCTAssertTrue(sanitized.contains("[REDACTED_API_KEY]"))
        XCTAssertTrue(sanitized.contains("[REDACTED_AWS_KEY]"))
        XCTAssertTrue(sanitized.contains("[REDACTED_GITHUB_TOKEN]"))
    }

    func testSanitizeDiffCompletelyExcludesSecretFiles() {
        let diff = """
        diff --git a/src/index.ts b/src/index.ts
        --- a/src/index.ts
        +++ b/src/index.ts
        @@ -1,3 +1,3 @@
        -const x = 1;
        +const x = 2;
        diff --git a/.env b/.env
        --- a/.env
        +++ b/.env
        @@ -0,0 +1,2 @@
        +SECRET_KEY=supersecret123
        +DATABASE_PASSWORD=productionpassword
        """
        let sanitized = SecretFilter.sanitizeDiff(diff)
        XCTAssertFalse(sanitized.contains("supersecret123"))
        XCTAssertFalse(sanitized.contains("productionpassword"))
        XCTAssertTrue(sanitized.contains("diff --git a/src/index.ts b/src/index.ts"))
        XCTAssertTrue(sanitized.contains("[EXCLUDED: Secret file diff omitted for safety]"))
    }

    func testQuotedValuesWithSpacesAreFullyRedacted() {
        let input = """
        PASSWORD="correct horse battery staple"
        export API_TOKEN='my super secret api token with spaces'
        "client_secret": "json secret with many spaces"
        """
        let sanitized = SecretFilter.sanitizeText(input)
        XCTAssertFalse(sanitized.contains("correct horse battery staple"))
        XCTAssertFalse(sanitized.contains("my super secret api token with spaces"))
        XCTAssertFalse(sanitized.contains("json secret with many spaces"))
        XCTAssertTrue(sanitized.contains("PASSWORD=\"[REDACTED_SECRET]\""))
        XCTAssertTrue(sanitized.contains("export API_TOKEN='[REDACTED_SECRET]'"))
        XCTAssertTrue(sanitized.contains("\"client_secret\": \"[REDACTED_SECRET]\""))
    }

    func testUnquotedValuesAreRedacted() {
        let input = "db_password=unquoted_secret_val123"
        let sanitized = SecretFilter.sanitizeText(input)
        XCTAssertFalse(sanitized.contains("unquoted_secret_val123"))
        XCTAssertTrue(sanitized.contains("db_password=[REDACTED_SECRET]"))
    }

    func testTokensEmbeddedInProseAreRedacted() {
        let input = "Please use OpenAI key sk-proj-1234567890abcdef12345678 to test the endpoint."
        let sanitized = SecretFilter.sanitizeText(input)
        XCTAssertFalse(sanitized.contains("sk-proj-1234567890abcdef12345678"))
        XCTAssertTrue(sanitized.contains("[REDACTED_API_KEY]"))
    }

    func testMultilinePrivateKeysAreRedacted() {
        let input = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABlwAAAAdzc2gtcn
        NhAAAAAwEAAQAAAYEAv9exampleMultilineKeyData1234567890
        -----END OPENSSH PRIVATE KEY-----
        """
        let sanitized = SecretFilter.sanitizeText(input)
        XCTAssertFalse(sanitized.contains("exampleMultilineKeyData1234567890"))
        XCTAssertTrue(sanitized.contains("[REDACTED_PRIVATE_KEY_BLOCK]"))
    }

    func testSecretLookingRenamedFilesAreDetectedAndExcluded() {
        XCTAssertTrue(SecretFilter.isSecretFile(path: "old_name.txt -> .env"))
        XCTAssertTrue(SecretFilter.isSecretFile(path: ".env -> new_name.txt"))
        XCTAssertTrue(SecretFilter.isSecretFile(path: "safe.txt -> server.key"))
        XCTAssertTrue(SecretFilter.isSecretFile(path: "credentials.json -> backup.json"))
        XCTAssertFalse(SecretFilter.isSecretFile(path: "old.txt -> new.txt"))

        let diff = """
        diff --git a/safe.txt b/.env
        similarity index 100%
        rename from safe.txt
        rename to .env
        """
        let sanitizedDiff = SecretFilter.sanitizeDiff(diff)
        XCTAssertTrue(sanitizedDiff.contains("[EXCLUDED: Secret file diff omitted for safety]"))
    }

    func testAllTextualFieldsInHandoffAreSanitized() {
        let project = ProjectContext(
            name: "Project sk-proj-1234567890abcdef12345678",
            repositoryPath: "/Users/dev/password=supersecret/repo",
            ecosystem: "Swift",
            remoteURL: "https://user:mypassword123@github.com/org/repo.git"
        )
        let state = CanonicalRepositoryState(
            branch: "feature/token-ghp_1234567890abcdefghijklmnopqrstuvwx",
            headCommit: "commit-hash",
            isClean: false,
            modifiedFiles: ["src/sk-proj-1234567890abcdef12345678.swift"],
            stagedFiles: [],
            untrackedFiles: [],
            diffSummary: DiffSummary(
                filesChanged: 1,
                additions: 10,
                deletions: 2,
                stagedAdditions: 5,
                stagedDeletions: 1,
                stagedFilesCount: 1,
                unstagedAdditions: 5,
                unstagedDeletions: 1,
                unstagedFilesCount: 1,
                files: [FileDelta(path: "src/token-sk-proj-1234567890abcdef12345678.swift", additions: 10, deletions: 2)],
                rawDiffSnippet: "diff --git a/file.txt b/file.txt\n+password=\"secret in diff\"",
                isTruncated: true
            ),
            refreshedAt: Date(),
            isStale: true,
            stalenessReason: "Refresh failed with key sk-proj-1234567890abcdef12345678"
        )
        let handoff = Handoff(
            project: project,
            currentGoal: "Goal with PASSWORD=\"secret goal value\"",
            completedWork: [ContextItem(text: "Done work with AWS key AKIAIOSFODNN7EXAMPLE")],
            currentState: state,
            importantFiles: [ImportantFile(path: "src/important-sk-proj-1234567890abcdef12345678.swift", reason: "Reason with token=secret123")],
            decisions: [Decision(text: "Decision with secret=mydecisionsecret")],
            nextTasks: [TaskItem(text: "Task with api_key: 'myapikey123'")],
            knownProblems: [ProblemItem(text: "Problem with secret: 'badpass'")],
            recentWork: [ContextItem(text: "Recent work with bearer Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.doNotLeakThisToken")],
            recentCommits: [Commit(hash: "abc", shortHash: "abc", author: "Dev <token=authsecret>", date: "2026-09-28", subject: "Fixed bug with PASSWORD='commit secret'")],
            detectedInstructions: [InstructionFile(path: "rules/instruction-sk-proj-1234567890abcdef12345678.md", filename: "rule-sk-proj-1234567890abcdef12345678.md", scope: "scope-ghp_1234567890abcdefghijklmnopqrstuvwx", content: "Instructions with API_KEY=\"rule secret\"")],
            todos: [TodoItem(file: "src/todo-sk-proj-1234567890abcdef12345678.swift", line: 10, kind: "TODO", comment: "Fix with pwd=secretpassword", isInsideChangedFile: true)],
            notes: "Notes with password=\"notes secret\""
        )

        let sanitized = SecretFilter.sanitizeHandoff(handoff)

        // Verify project
        XCTAssertFalse(sanitized.project.name.contains("sk-proj-"))
        XCTAssertFalse(sanitized.project.repositoryPath.contains("supersecret"))
        XCTAssertFalse(sanitized.project.remoteURL?.contains("mypassword123") ?? false)

        // Verify state & staleness
        XCTAssertFalse(sanitized.currentState.branch.contains("ghp_"))
        XCTAssertFalse(sanitized.currentState.stalenessReason?.contains("sk-proj-") ?? false)
        XCTAssertFalse(sanitized.currentState.modifiedFiles[0].contains("sk-proj-"))

        // Verify diff metadata survived
        let diff = sanitized.currentState.diffSummary!
        XCTAssertEqual(diff.stagedAdditions, 5)
        XCTAssertEqual(diff.stagedDeletions, 1)
        XCTAssertEqual(diff.stagedFilesCount, 1)
        XCTAssertEqual(diff.unstagedAdditions, 5)
        XCTAssertEqual(diff.unstagedDeletions, 1)
        XCTAssertEqual(diff.unstagedFilesCount, 1)
        XCTAssertTrue(diff.isTruncated)
        XCTAssertFalse(diff.files[0].path.contains("sk-proj-"))
        XCTAssertFalse(diff.rawDiffSnippet?.contains("secret in diff") ?? false)

        // Verify other textual fields
        XCTAssertFalse(sanitized.currentGoal.contains("secret goal value"))
        XCTAssertFalse(sanitized.completedWork[0].text.contains("AKIAIOSFODNN7EXAMPLE"))
        XCTAssertFalse(sanitized.importantFiles[0].path.contains("sk-proj-"))
        XCTAssertFalse(sanitized.importantFiles[0].reason.contains("secret123"))
        XCTAssertFalse(sanitized.decisions[0].text.contains("mydecisionsecret"))
        XCTAssertFalse(sanitized.nextTasks[0].text.contains("myapikey123"))
        XCTAssertFalse(sanitized.knownProblems[0].text.contains("badpass"))
        XCTAssertFalse(sanitized.recentWork[0].text.contains("doNotLeakThisToken"))
        XCTAssertFalse(sanitized.recentCommits[0].author.contains("authsecret"))
        XCTAssertFalse(sanitized.recentCommits[0].subject.contains("commit secret"))
        XCTAssertFalse(sanitized.detectedInstructions[0].path.contains("sk-proj-"))
        XCTAssertFalse(sanitized.detectedInstructions[0].filename.contains("sk-proj-"))
        XCTAssertFalse(sanitized.detectedInstructions[0].scope.contains("ghp_"))
        XCTAssertFalse(sanitized.detectedInstructions[0].content.contains("rule secret"))
        XCTAssertFalse(sanitized.todos[0].file.contains("sk-proj-"))
        XCTAssertFalse(sanitized.todos[0].comment.contains("secretpassword"))
        XCTAssertFalse(sanitized.notes?.contains("notes secret") ?? false)
    }
}
