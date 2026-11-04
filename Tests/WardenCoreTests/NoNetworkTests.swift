import XCTest

/// Warden's promise is "zero network". An unsandboxed app has no entitlement to enforce it,
/// so it is enforced here, on the source code itself.
final class NoNetworkTests: XCTestCase {
    func testNoSourceUsesANetworkAPI() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let forbidden = [
            "URLSession", "URLRequest", "NWConnection", "NWListener", "NWPathMonitor", "import Network",
            "CFStream", "WKWebView", "CFSocket", "getaddrinfo", "URLDownload"
        ]
        var scanned = 0
        for folder in ["Sources", "App"] {
            guard let enumerator = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let source = try String(contentsOf: url, encoding: .utf8)
                scanned += 1
                for token in forbidden {
                    XCTAssertFalse(source.contains(token), "\(url.lastPathComponent) uses \(token)")
                }
            }
        }
        XCTAssertGreaterThan(scanned, 20)
    }
}
