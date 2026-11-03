import XCTest
@testable import GTasksTray

@MainActor
final class OAuthCallbackTests: XCTestCase {
    func testLoopbackCallbackValidatesStateBeforeReturningCode() async throws {
        let callback = try OAuthCallback(state: "test-state")
        defer { callback.stop() }
        var events = callback.events.makeAsyncIterator()
        guard case .ready(let port) = try await events.next() else {
            return XCTFail("The callback server did not start")
        }

        let base = "http://127.0.0.1:\(port)/"
        let session = URLSession(configuration: .ephemeral)
        let (_, rejected) = try await session.data(from: URL(string: base + "?state=wrong&code=ignored")!)
        XCTAssertEqual((rejected as? HTTPURLResponse)?.statusCode, 400)

        let (_, accepted) = try await session.data(from: URL(string: base + "?state=test-state&code=abc%2B123")!)
        XCTAssertEqual((accepted as? HTTPURLResponse)?.statusCode, 200)
        guard case .code(let code) = try await events.next() else {
            return XCTFail("The valid callback did not return a code")
        }
        XCTAssertEqual(code, "abc+123")
    }
}
