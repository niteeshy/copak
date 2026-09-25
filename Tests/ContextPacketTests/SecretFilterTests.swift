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
}
