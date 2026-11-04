@testable import WardenCore
import XCTest

final class RedactionTests: XCTestCase {
    private func assertMasked(_ secret: String, in text: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let redacted = SecretRedactor.redact(text ?? secret)
        XCTAssertFalse(redacted.contains(secret), "leaked: \(redacted)", file: file, line: line)
        XCTAssertTrue(redacted.contains("[masked:"), file: file, line: line)
    }

    func testKnownTokenShapes() {
        let secrets = [
            "sk-ant-api03-AbCdEfGhIjKlMnOp_qrstuv",
            "sk-proj-abcdefghijklmnop1234",
            "ghp_abcdefghijklmnopqrstuvwxyz012345",
            "gho_abcdefghijklmnopqrstuvwxyz012345",
            "github_pat_11ABCDEFG0abcdefghijkl",
            "xoxb-1234567890-abcdefghij",
            "AKIAIOSFODNN7EXAMPLE",
            "AIzaSyD-abcdefghijklmnopqrstuvwxyz12345",
            "npm_abcdefghijklmnopqrstuvwxyz",
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.c2lnbmF0dXJl"
        ]
        for secret in secrets { assertMasked(secret) }
    }

    func testAuthorizationHeaders() {
        assertMasked("abc123def456", in: #""Authorization": "Bearer abc123def456""#)
        assertMasked("dXNlcjpwYXNz", in: "Authorization: Basic dXNlcjpwYXNz")
        assertMasked("s3cretvalue", in: #"headers = { "X-Auth-Token" = "s3cretvalue" }"#)
    }

    func testAssignments() {
        assertMasked("hunter2hunter2", in: #""password": "hunter2hunter2""#)
        assertMasked("abcd1234", in: "API_KEY=abcd1234")
        assertMasked("abcd1234", in: "api-key: abcd1234")
        assertMasked("abcd1234", in: #"client_secret = "abcd1234""#)
        assertMasked("abcd1234", in: "\"GITHUB_TOKEN\": \"abcd1234\"")
    }

    func testURLCredentialsAndQueries() {
        assertMasked("p4ssw0rd", in: "https://user:p4ssw0rd@proxy.example:8080")
        assertMasked("abcd1234", in: "https://x.example/a?token=abcd1234&b=1")
    }

    func testPrivateKeyBlock() {
        let block = "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXk\nabcdef\n-----END OPENSSH PRIVATE KEY-----"
        XCTAssertFalse(SecretRedactor.redact(block).contains("b3BlbnNzaC1rZXk"))
    }

    func testUnknownHighEntropyTokens() {
        assertMasked("Zk9qT3xW7vLp2mNc8RtY4bHd6JsQ1aFe", in: "value: Zk9qT3xW7vLp2mNc8RtY4bHd6JsQ1aFe")
    }

    func testOrdinaryConfigSurvives() {
        let text = """
        "url": "https://mcp.atlassian.com/v1/sse",
        "command": "npx -y @modelcontextprotocol/server-filesystem /Users/me/projects/my-long-project-name",
        "model": "claude-opus-5-5",
        "tokenLimit": 100,
        "hasTrustDialogAccepted": true,
        "authType": "oauth"
        """
        XCTAssertEqual(SecretRedactor.redact(text), text)
    }

    func testDifferentSecretsKeepDifferentMarkers() {
        let first = SecretRedactor.redact("API_KEY=first-value-1")
        let second = SecretRedactor.redact("API_KEY=second-value-2")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, SecretRedactor.redact("API_KEY=first-value-1"))
    }

    func testRedactionIsIdempotent() {
        let once = SecretRedactor.redact("password: hunter2hunter2 and sk-ant-api03-AbCdEfGhIjKl")
        XCTAssertEqual(SecretRedactor.redact(once), once)
    }

    func testMultipleSecretsOnOneLine() {
        let redacted = SecretRedactor.redact("a ghp_abcdefghijklmnopqrstuvwxyz012345 b sk-ant-api03-AbCdEfGhIjKl c")
        XCTAssertFalse(redacted.contains("ghp_"))
        XCTAssertFalse(redacted.contains("sk-ant"))
    }
}
