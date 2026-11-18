import Foundation
import Security
import CryptoKit

public enum ClientError: LocalizedError {
    case address, response, http(Int, String), keychain(OSStatus), invalidServer
    public var errorDescription: String? {
        switch self {
        case .address: "Enter a full server address starting with https:// or http://."
        case .response: "The server returned a response Zakka could not read."
        case .http(_, let message): message
        case .keychain(let status): "The session could not be stored securely (\(status))."
        case .invalidServer: "This address did not respond as a Zakka server."
        }
    }
}

public actor ZakkaClient {
    public nonisolated let baseURL: URL
    private let session: URLSession
    private var cookie: String?
    private let expired: @Sendable () async -> Void

    public init(address: String, onExpired: @escaping @Sendable () async -> Void = {}) throws {
        guard var parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), ["https","http"].contains(scheme),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { throw ClientError.address }
        var path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path == "api/v1" { path = "" }
        else if path.hasSuffix("/api/v1") { path.removeLast(7) }
        parts.path = path.isEmpty ? "" : "/" + path
        guard let url = parts.url else { throw ClientError.address }
        self.baseURL = url
        self.expired = onExpired
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        self.cookie = try SessionKeychain.get(url.absoluteString)
    }

    public func data(_ path: String) async throws -> Data {
        let isMedia = path.hasPrefix("/assets/") || path.hasPrefix("/api/v1/assets/")
        guard isMedia, let cookie else { return try await send(path).0 }
        let key = SHA256.hash(data: Data((baseURL.absoluteString + "|" + cookie + "|" + path).utf8))
            .map { String(format: "%02x", $0) }.joined()
        let url = URL.cachesDirectory.appending(path: "zakka-\(key)")
        if FileManager.default.fileExists(atPath: url.path) { return try Data(contentsOf: url) }
        let bytes = try await send(path).0
        try bytes.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        return bytes
    }
    public func json(_ path: String, method: String = "GET", body: JSONValue? = nil) async throws -> JSONValue {
        let (data, resp) = try await send(path, method: method, body: try body.map { try JSONEncoder().encode($0) })
        if path == "/auth/login" || path == "/auth/register" {
            let headers = resp.allHeaderFields.reduce(into: [String:String]()) { if let key = $1.key as? String { $0[key] = String(describing: $1.value) } }
            guard let token = HTTPCookie.cookies(withResponseHeaderFields: headers, for: baseURL)
                .first(where: { $0.name == "scrapbook_session" })?.value else { throw ClientError.response }
            try SessionKeychain.set(token, baseURL.absoluteString)
            cookie = token
        }
        if path == "/auth/logout" { try forget() }
        return data.isEmpty ? .null : try JSONDecoder().decode(JSONValue.self, from: data)
    }
    public func hasSession() -> Bool { cookie != nil }
    public func forget() throws {
        cookie = nil
        try SessionKeychain.set(nil, baseURL.absoluteString)
    }
    public func upload(_ file: Data, filename: String, mime: String) async throws -> JSONValue {
        guard file.count <= 20 * 1024 * 1024 else { throw ClientError.http(413, "Choose an image smaller than 20 MiB.") }
        let boundary = UUID().uuidString
        let safe = String(filename.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != "\"" && $0 != "\\" })
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safe)\"\r\nContent-Type: \(mime)\r\n\r\n".utf8)
        body.append(file); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let (data, _) = try await send("/assets/uploads", method: "POST", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func send(_ path: String, method: String = "GET", body: Data? = nil,
                      contentType: String = "application/json") async throws -> (Data, HTTPURLResponse) {
        let relative = path.hasPrefix("/api/v1/") ? String(path.dropFirst(7)) : path
        guard relative.hasPrefix("/"), !relative.hasPrefix("//"),
              let url = URL(string: baseURL.absoluteString + "/api/v1" + relative) else { throw ClientError.address }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let cookie { req.setValue("scrapbook_session=\(cookie)", forHTTPHeaderField: "Cookie") }
        let (data, response) = try await session.data(for: req)
        guard let response = response as? HTTPURLResponse else { throw ClientError.response }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401, cookie != nil, !["/auth/register","/auth/login"].contains(relative) {
                try forget()
                await expired()
            }
            let message = (try? JSONDecoder().decode(JSONValue.self, from: data))?["error"]["message"].text
            throw ClientError.http(response.statusCode, message?.isEmpty == false ? message! : "Server returned HTTP \(response.statusCode).")
        }
        return (data, response)
    }
}

// Do not forward session credentials or a sign-in body to redirect destinations.
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

private enum SessionKeychain {
    static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.zakka.ZakkaPad.session", kSecAttrAccount as String: account]
    }
    static func get(_ account: String) throws -> String? {
        var q = query(account); q[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let d = result as? Data else { throw ClientError.keychain(status) }
        return String(decoding: d, as: UTF8.self)
    }
    static func set(_ token: String?, _ account: String) throws {
        let q = query(account)
        let removed = SecItemDelete(q as CFDictionary)
        guard removed == errSecItemNotFound || removed == errSecSuccess else { throw ClientError.keychain(removed) }
        guard let token else { return }
        var entry = q
        entry[kSecValueData as String] = Data(token.utf8)
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(entry as CFDictionary, nil)
        guard status == errSecSuccess else { throw ClientError.keychain(status) }
    }
}
