import XCTest
import UIKit

@MainActor
final class LiveStudioTests: XCTestCase {
    func testCreateEditRestoreAndExport() async throws {
        guard let address = ProcessInfo.processInfo.environment["ZAKKA_TEST_SERVER"] else {
            throw XCTSkip("Set TEST_RUNNER_ZAKKA_TEST_SERVER to an isolated local Zakka origin to run the live journey.")
        }
        let endpoint = try XCTUnwrap(URL(string: address + "/api/v1"))
        let suffix = UUID().uuidString
        let email = "ipad-\(suffix)@example.test", password = UUID().uuidString
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config)
        func request(_ path: String, _ method: String = "GET", json: [String:Any]? = nil) async throws -> [String:Any] {
            var req = URLRequest(url:endpoint.appending(path:path))
            req.httpMethod = method
            if let json { req.setValue("application/json",forHTTPHeaderField:"Content-Type");req.httpBody = try JSONSerialization.data(withJSONObject:json) }
            let (d,r) = try await session.data(for:req)
            XCTAssertTrue(200..<300 ~= (r as? HTTPURLResponse)?.statusCode ?? 0)
            return try XCTUnwrap(JSONSerialization.jsonObject(with:d) as? [String:Any])
        }
        _ = try await request("auth/register","POST",json:["displayName":"Journey test","email":email,"password":password])
        let image = UIGraphicsImageRenderer(size:CGSize(width:64,height:64)).image { r in
            UIColor.systemTeal.setFill();r.fill(CGRect(x:0,y:0,width:64,height:64))
        }
        let boundary = UUID().uuidString
        var upload = URLRequest(url:endpoint.appending(path:"assets/uploads"))
        upload.httpMethod = "POST"
        upload.setValue("multipart/form-data; boundary=\(boundary)",forHTTPHeaderField:"Content-Type")
        var bytes = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"journey.png\"\r\nContent-Type: image/png\r\n\r\n".utf8)
        bytes.append(try XCTUnwrap(image.pngData()));bytes.append(Data("\r\n--\(boundary)--\r\n".utf8))
        upload.httpBody = bytes
        let (_,r) = try await session.data(for:upload)
        XCTAssertEqual((r as? HTTPURLResponse)?.statusCode,201)

        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Password AutoFill") { alert in
            let cancel = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Not Now", "Not now", "Don't Save"])).firstMatch
            if cancel.exists { cancel.tap(); return true }
            return false
        }
        app.launch()
        // A simulator can already be signed in; never modify another account's books.
        if app.buttons["nav.Settings"].waitForExistence(timeout:3) {
            app.buttons["nav.Settings"].tap()
            app.buttons["Sign out"].tap()
            app.alerts.buttons["Sign out"].tap()
        }
        let server = app.textFields["server"]
        XCTAssertTrue(server.waitForExistence(timeout:10))
        server.tap()
        if let old = server.value as? String,old != "Server URL",!old.isEmpty {
            server.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.count))
        }
        server.typeText(address)
        app.textFields["email"].tap(); app.textFields["email"].typeText(email)
        app.secureTextFields["password"].tap();app.secureTextFields["password"].typeText(password)
        app.buttons["Sign in"].tap()
        XCTAssertTrue(app.buttons["New book"].waitForExistence(timeout:15))
        let notNow = app.alerts.buttons["Not Now"]
        if notNow.waitForExistence(timeout:3) { notNow.tap() }
        // Check a fresh process restores the Keychain session, independent of the password prompt.
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["New book"].waitForExistence(timeout:15))
        app.buttons["New book"].tap()
        XCTAssertTrue(app.textFields["book.title"].waitForExistence(timeout:5))
        app.textFields["book.title"].tap(); app.textFields["book.title"].typeText("Journey book")
        app.buttons["Create"].tap()
        let add = app.buttons["Add layer"]
        XCTAssertTrue(add.waitForExistence(timeout:15))
        add.tap();app.buttons["Photo"].tap()
        let photo = app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "journey.png")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout:10));photo.tap()
        add.tap();app.buttons["Text"].tap()
        let caption = app.descendants(matching:.any)["layer.text"].firstMatch
        caption.tap();caption.typeText("Saved from iPad")
        app.buttons["Add text"].tap()
        app.buttons["Add page"].tap()
        let books = try await request("books")
        let created = try XCTUnwrap((books["books"] as? [[String:Any]])?.first)
        let bookID = try XCTUnwrap(created["id"] as? String)
        let detail = try await request("books/\(bookID)")
        let entries = try XCTUnwrap(detail["pages"] as? [[String:Any]])
        let first = try XCTUnwrap(entries.first?["pageId"] as? String)
        let page = try await request("pages/\(first)")
        let layers = try XCTUnwrap((page["document"] as? [String:Any])?["layers"] as? [[String:Any]])
        XCTAssertEqual(layers.compactMap{$0["kind"] as? String},["photo","text"])
        XCTAssertEqual(layers.last?["text"] as? String,"Saved from iPad")
        app.buttons["film.1"].tap()
        app.buttons["Editor options"].tap()
        let later = app.buttons["Move page later"]
        XCTAssertTrue(later.waitForExistence(timeout: 5))
        later.tap()
        var reordered = false
        for _ in 0..<20 {
            let updated = try await request("books/\(bookID)")
            let ids = (updated["pages"] as? [[String:Any]])?.compactMap { $0["pageId"] as? String } ?? []
            if ids.count > 1, ids[1] == first { reordered = true; break }
            try await Task.sleep(for: .milliseconds(150))
        }
        XCTAssertTrue(reordered, "The filmstrip order must reach the server")
        app.buttons["Export book or page"].tap()
        app.buttons["Create export"].tap()
        XCTAssertTrue(app.buttons["Share exported file"].waitForExistence(timeout:75))
        app.terminate();app.launch()
        XCTAssertTrue(app.buttons["featured.book"].waitForExistence(timeout:20))
    }
}
