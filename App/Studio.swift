import CryptoKit
import Foundation
import Observation
import ZakkaCore

struct WorkspaceSnapshot: Codable {
    var account: JSONValue
    var books: [JSONValue] = []
    var photos: [JSONValue] = []
    var albums: [JSONValue] = []
    var details: [String: JSONValue] = [:]
    var pages: [String: JSONValue] = [:]
}

@Observable @MainActor
final class Studio {
    var client: ZakkaClient?
    var snapshot: WorkspaceSnapshot?
    var offline = false
    var restoring = true
    var refreshing = false
    var error: String?
    var version = ""
    var address = UserDefaults.standard.string(forKey: "lastServer") ?? ""
    var profiles = UserDefaults.standard.stringArray(forKey: "servers") ?? []
    var activeBook: String?
    private var cacheFolder: URL?
    private var loadGeneration = UUID()
    private(set) var dirtyPages: [String: JSONValue] = [:]
    private var timers: [String: Task<Void, Never>] = [:]
    private var saving: Set<String> = []
    var isSignedIn: Bool { snapshot != nil }
    var canEdit: Bool { isSignedIn && !offline }

    func restore() async {
        defer { restoring = false }
        guard !address.isEmpty else { return }
        do {
            let c = try makeClient(address)
            guard await c.hasSession() else { return }
            client = c
            do {
                let auth = try await c.json("/auth/session")
                try enter(account: auth["account"], client: c)
                await refresh()
            } catch let e as URLError {
                guard let id = UserDefaults.standard.string(forKey: lastAccountKey(c)),
                      let cached = try loadCache(accountID: id, client: c) else { throw e }
                snapshot = cached; offline = true
            }
        } catch { self.error = error.localizedDescription }
    }

    func connect(address: String, email: String, password: String, name: String, register: Bool) async throws {
        let c = try makeClient(address)
        let health = try await c.json("/health")
        guard health["service"] == "zakka-api", health["status"] == "ok" else { throw ClientError.invalidServer }
        var body: JSONValue = ["email": .string(email), "password": .string(password)]
        if register { body["displayName"] = .string(name) }
        let auth = try await c.json(register ? "/auth/register" : "/auth/login", method: "POST", body: body)
        try enter(account: auth["account"], client: c)
        version = health["version"].text
        self.address = c.baseURL.absoluteString
        UserDefaults.standard.set(self.address, forKey: "lastServer")
        if !profiles.contains(self.address) { profiles.append(self.address); UserDefaults.standard.set(profiles, forKey: "servers") }
        await refresh()
    }

    private func makeClient(_ address: String) throws -> ZakkaClient {
        let generation = UUID()
        loadGeneration = generation
        return try ZakkaClient(address: address) { [weak self] in await self?.expired(generation) }
    }

    private func lastAccountKey(_ c: ZakkaClient) -> String { "account:" + c.baseURL.absoluteString }
    private func loadCache(accountID: String, client: ZakkaClient) throws -> WorkspaceSnapshot? {
        let key = SHA256.hash(data: Data((client.baseURL.absoluteString + "|" + accountID).utf8)).map { String(format: "%02x", $0) }.joined()
        let folder = URL.applicationSupportDirectory.appending(path: key, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        cacheFolder = folder
        let pending = folder.appending(path: "pending.json")
        dirtyPages = FileManager.default.fileExists(atPath: pending.path)
            ? try JSONDecoder().decode([String:JSONValue].self, from: Data(contentsOf: pending)) : [:]
        let url = folder.appending(path: "workspace.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(WorkspaceSnapshot.self, from: Data(contentsOf: url))
    }
    private func enter(account: JSONValue, client: ZakkaClient) throws {
        guard !account.id.isEmpty else { throw ClientError.response }
        self.client = client
        self.snapshot = try loadCache(accountID: account.id, client: client) ?? WorkspaceSnapshot(account: account)
        snapshot?.account = account; offline = false
        UserDefaults.standard.set(account.id, forKey: lastAccountKey(client))
    }
    private func expired(_ generation: UUID) {
        guard generation == loadGeneration else { return }
        clear(); error = "Your session expired. Sign in again to continue."
    }
    private func clear() {
        loadGeneration = UUID()
        timers.values.forEach { $0.cancel() }; timers = [:]; saving = []; dirtyPages = [:]
        snapshot = nil; client = nil; cacheFolder = nil; activeBook = nil; offline = false; refreshing = false
    }
    func signOut() async throws {
        if let client {
            if !offline { _ = try await client.json("/auth/logout", method: "POST") }
            else { try await client.forget() }
        }
        clear()
    }
    private func cache() {
        guard let cacheFolder, let snapshot else { return }
        do { try JSONEncoder().encode(snapshot).write(to: cacheFolder.appending(path: "workspace.json"), options: [.atomic, .completeFileProtectionUnlessOpen]) }
        catch { self.error = "Could not cache this workspace: \(error.localizedDescription)" }
    }
    func refresh() async {
        guard let client, !refreshing else { return }
        let gen = loadGeneration; refreshing = true
        defer { if loadGeneration == gen { refreshing = false } }
        do {
            async let b = client.json("/books"), a = client.json("/assets"), albums = client.json("/albums"), health = client.json("/health")
            let (books, photos, groups, status) = try await (b,a,albums,health)
            guard gen == loadGeneration else { return }
            snapshot?.books = books["books"].items; snapshot?.photos = photos["assets"].items
            snapshot?.albums = groups["albums"].items; version = status["version"].text
            offline = false; cache()
            for id in dirtyPages.keys { schedule(id, immediate: true) }
            // Covers are page documents, not thumbnails in the books response.
            for book in books["books"].items {
                guard gen == loadGeneration else { return }
                let detail = try await bookDetail(book.id)
                if let first = detail["pages"].items.first { _ = try await page(first["pageId"].text) }
            }
        } catch { if gen == loadGeneration { handle(error) } }
    }
    func handle(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        if error is URLError { offline = true }
        self.error = error.localizedDescription
    }
    func bookDetail(_ id: String) async throws -> JSONValue {
        if offline, let cached = snapshot?.details[id] { return cached }
        guard let client, !offline else { throw URLError(.notConnectedToInternet) }
        let d = try await client.json("/books/\(id)")
        guard client === self.client else { throw CancellationError() }
        snapshot?.details[id] = d; cache(); return d
    }
    func page(_ id: String) async throws -> JSONValue {
        if offline, let p = snapshot?.pages[id] { return p }
        guard let client, !offline else { throw URLError(.notConnectedToInternet) }
        var p = try await client.json("/pages/\(id)")
        guard client === self.client else { throw CancellationError() }
        if let held = dirtyPages[id] { p["document"] = held }
        snapshot?.pages[id] = p; cache(); return p
    }
    func cover(_ book: JSONValue) -> JSONValue? {
        guard let id = snapshot?.details[book.id]?["pages"].items.first?["pageId"].text else { return nil }
        return snapshot?.pages[id]?["document"]
    }
    func mutation(_ path: String, _ method: String, _ body: JSONValue? = nil) async throws -> JSONValue {
        guard let client, canEdit else { throw URLError(.notConnectedToInternet) }
        return try await client.json(path, method: method, body: body)
    }
    func edit(id: String, document: JSONValue) {
        guard canEdit, snapshot?.pages[id] != nil else { return }
        snapshot?.pages[id]?["document"] = document
        dirtyPages[id] = document
        persistPending(); schedule(id)
    }
    private func persistPending() {
        guard let cacheFolder else { return }
        do { try JSONEncoder().encode(dirtyPages).write(to: cacheFolder.appending(path: "pending.json"), options: [.atomic, .completeFileProtectionUnlessOpen]) }
        catch { self.error = "Could not preserve pending edits: \(error.localizedDescription)" }
    }
    private func schedule(_ id: String, immediate: Bool = false) {
        timers[id]?.cancel()
        timers[id] = Task {
            if !immediate { try? await Task.sleep(for: .milliseconds(700)) }
            guard !Task.isCancelled else { return }
            // Detach the request lifetime from subsequent debounce timers. Only one save per page may run.
            timers.removeValue(forKey: id)
            await save(id)
        }
    }
    func flush() async throws {
        for id in Array(dirtyPages.keys) {
            timers[id]?.cancel(); timers[id] = nil
            while saving.contains(id) { try await Task.sleep(for: .milliseconds(50)) }
            await save(id)
            if dirtyPages[id] != nil { throw ClientError.http(409, "Edits have not reached the server. Reconnect and retry.") }
        }
    }
    private func save(_ id: String) async {
        guard canEdit, !saving.contains(id), let client, let document = dirtyPages[id] else { return }
        saving.insert(id)
        do {
            let p = try await client.json("/pages/\(id)", method: "PATCH", body: ["document": document])
            guard self.client === client else { return }
            saving.remove(id)
            if dirtyPages[id] == document {
                dirtyPages.removeValue(forKey: id); snapshot?.pages[id] = p; persistPending(); cache()
            } else { schedule(id, immediate: true) }
        } catch { if self.client === client { saving.remove(id); handle(error) } }
    }
}
