import AppKit
import CryptoKit
import Foundation
import Network
import Security

struct GoogleOAuthClient: Codable, Equatable {
    let id: String
    let secret: String?

    static func load(from url: URL) throws -> Self {
        struct Download: Decodable {
            struct Installed: Decodable {
                let client_id: String
                let client_secret: String?
            }

            let installed: Installed
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: 65_537), data.count <= 65_536,
              let config = try? JSONDecoder().decode(Download.self, from: data),
              config.installed.client_id.hasSuffix(".apps.googleusercontent.com") else {
            throw GoogleOAuth.Error.invalidClientFile
        }
        return Self(id: config.installed.client_id, secret: config.installed.client_secret)
    }
}

struct GoogleCredentials: Codable {
    let client: GoogleOAuthClient
    var refreshToken: String?
}

enum CredentialStore {
    struct StoreError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Pęk kluczy macOS zwrócił błąd (\(status))." }
    }

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "pl.gtaskstray.app.google-oauth",
            kSecAttrAccount as String: "Google Tasks"
        ]
    }

    static func load() throws -> GoogleCredentials? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw StoreError(status: status)
        }
        return try JSONDecoder().decode(GoogleCredentials.self, from: data)
    }

    static func save(_ credentials: GoogleCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let values = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StoreError(status: status) }
    }
}

@MainActor
struct GoogleOAuth {
    struct Token: Decodable {
        let access_token: String
        let expires_in: Int
        let refresh_token: String?
    }

    enum Error: LocalizedError {
        case invalidClientFile
        case browserUnavailable
        case callbackUnavailable
        case timedOut
        case consentDenied
        case missingRefreshToken
        case requestFailed(status: Int, code: String?)

        var errorDescription: String? {
            switch self {
            case .invalidClientFile:
                "Wybierz plik JSON pobrany z Google Cloud dla klienta OAuth typu Desktop app."
            case .browserUnavailable:
                "Nie udało się otworzyć przeglądarki."
            case .callbackUnavailable:
                "Nie udało się odebrać odpowiedzi z przeglądarki. Spróbuj zalogować się ponownie."
            case .timedOut:
                "Upłynął czas na zalogowanie. Spróbuj ponownie."
            case .consentDenied:
                "Google nie udzielił dostępu do zadań."
            case .missingRefreshToken:
                "Google nie zwrócił tokenu do synchronizacji. Spróbuj zalogować się ponownie."
            case .requestFailed(_, "invalid_grant"):
                "Sesja Google wygasła. Zaloguj się ponownie."
            case .requestFailed(_, "invalid_client"), .requestFailed(_, "unauthorized_client"):
                "Google odrzucił klienta OAuth. Wybierz aktualny plik JSON typu Desktop app."
            case .requestFailed(let status, _):
                "Logowanie Google zakończyło się błędem (HTTP \(status))."
            }
        }
    }

    private struct TokenError: Decodable {
        let error: String
    }

    func signIn(client: GoogleOAuthClient) async throws -> Token {
        let verifier = try randomURLSafeString()
        let state = try randomURLSafeString()
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let callback = try OAuthCallback(state: state)
        let redirect: String
        let code: String

        do {
            defer { callback.stop() }
            var events = callback.events.makeAsyncIterator()
            guard case .ready(let port) = try await events.next() else {
                try Task.checkCancellation()
                throw Error.callbackUnavailable
            }
            redirect = "http://127.0.0.1:\(port)/"
            var authorization = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            authorization.queryItems = [
                URLQueryItem(name: "client_id", value: client.id),
                URLQueryItem(name: "redirect_uri", value: redirect),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/tasks"),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent select_account"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256")
            ]
            guard let url = authorization.url, NSWorkspace.shared.open(url) else {
                throw Error.browserUnavailable
            }
            guard case .code(let value) = try await events.next() else {
                try Task.checkCancellation()
                throw Error.callbackUnavailable
            }
            code = value
        }

        return try await exchange(client: client, parameters: [
            "grant_type": "authorization_code",
            "redirect_uri": redirect,
            "code": code,
            "code_verifier": verifier
        ])
    }

    func refresh(client: GoogleOAuthClient, refreshToken: String) async throws -> Token {
        try await exchange(client: client, parameters: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ])
    }

    private func exchange(client: GoogleOAuthClient, parameters: [String: String]) async throws -> Token {
        var fields = parameters
        fields["client_id"] = client.id
        fields["client_secret"] = client.secret
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let body = fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&")
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let code = try? JSONDecoder().decode(TokenError.self, from: data).error
            throw Error.requestFailed(status: http.statusCode, code: code)
        }
        return try JSONDecoder().decode(Token.self, from: data)
    }

    private func randomURLSafeString() throws -> String {
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw Error.callbackUnavailable }
        return Self.base64URL(bytes)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

final class OAuthCallback {
    enum Event: Sendable {
        case ready(UInt16)
        case code(String)
    }

    let events: AsyncThrowingStream<Event, Swift.Error>

    private let listener: NWListener
    private let continuation: AsyncThrowingStream<Event, Swift.Error>.Continuation
    private let timeout: DispatchWorkItem

    init(state: String) throws {
        let queue = DispatchQueue(label: "pl.gtaskstray.oauth-callback")
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener

        let (events, continuation) = AsyncThrowingStream<Event, Swift.Error>.makeStream()
        self.events = events
        self.continuation = continuation
        timeout = DispatchWorkItem {
            continuation.finish(throwing: GoogleOAuth.Error.timedOut)
        }

        listener.stateUpdateHandler = { [weak listener] status in
            switch status {
            case .ready:
                if let port = listener?.port {
                    continuation.yield(.ready(port.rawValue))
                } else {
                    continuation.finish(throwing: GoogleOAuth.Error.callbackUnavailable)
                }
            case .failed(let error):
                continuation.finish(throwing: error)
            default:
                break
            }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
            Self.receive(on: connection, state: state, continuation: continuation)
        }
        listener.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 180, execute: timeout)
    }

    func stop() {
        timeout.cancel()
        listener.cancel()
        continuation.finish()
    }

    private static func receive(
        on connection: NWConnection,
        state: String,
        continuation: AsyncThrowingStream<Event, Swift.Error>.Continuation,
        buffer: Data = Data()
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192 - buffer.count) { data, _, done, error in
            let request = buffer + (data ?? Data())
            if let header = String(data: request, encoding: .utf8), header.contains("\r\n\r\n") {
                let result = parse(header, expectedState: state)
                let status = result == nil ? "400 Bad Request" : "200 OK"
                let message: String
                switch result {
                case .success: message = "Odebrano odpowiedź Google. Wróć do GTasksTray, aby sprawdzić połączenie."
                case .failure: message = "Google nie udzielił dostępu. Wróć do GTasksTray."
                case nil: message = "Nieprawidłowe żądanie."
                }
                let body = "<!doctype html><html lang=\"pl\"><meta charset=\"utf-8\"><title>GTasksTray</title><p>\(message)</p></html>"
                let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
                    + "Content-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                    switch result {
                    case .success(let code): continuation.yield(.code(code))
                    case .failure(let error): continuation.finish(throwing: error)
                    case nil: break
                    }
                })
            } else if request.count < 8192, !done, error == nil {
                receive(on: connection, state: state, continuation: continuation, buffer: request)
            } else {
                connection.cancel()
            }
        }
    }

    private static func parse(
        _ header: String,
        expectedState: String
    ) -> Result<String, GoogleOAuth.Error>? {
        let line = header.components(separatedBy: "\r\n")[0].split(separator: " ")
        guard line.count == 3, line[0] == "GET", line[1].hasPrefix("/?"),
              let query = URLComponents(string: "http://127.0.0.1" + line[1])?.queryItems,
              query.first(where: { $0.name == "state" })?.value == expectedState else {
            return nil
        }
        if let code = query.first(where: { $0.name == "code" })?.value, !code.isEmpty {
            return .success(code)
        }
        return .failure(.consentDenied)
    }
}
