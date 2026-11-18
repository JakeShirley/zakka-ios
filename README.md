# Zakka for iPad

Zakka is a native iPad workspace for books and photos on an existing [Zakka server](https://github.com/JakeShirley/zakka). This is an initial implementation of the [native client roadmap](docs/ipad-app-plan.md), not a claim of full web-editor parity.

## Run

1. Start a Zakka server. Its `GET /api/v1/health` endpoint must return `service: "zakka-api"`.
2. Open `ZakkaPad.xcodeproj` with Xcode 27 or later. Select the **ZakkaPad** scheme and an iPad running iPadOS 27 or later. For a physical device, choose your own signing team.
3. Enter the server origin (for example, `http://127.0.0.1:8080` **in the simulator**) and sign in or register. A physical iPad needs a reachable LAN address or HTTPS endpoint, not the Mac's loopback address. Prefer HTTPS; use plain HTTP only on trusted local networks.

There are no embedded server credentials or demo fixtures. A fresh account starts empty. Use **Photos → Import** for images, then **Books → New book**. In the editor, use **Add** for photos or text and tap a layer to select it. Press and hold a filmstrip thumbnail for page ordering and duplication. **Export** asks the server to render a shareable PDF, PNG or ZIP.

## What's here

- Server sign-in, registration, logout, saved addresses and Keychain session restoration. Metadata and media caches are isolated by server/account or session. Cached books and photos can be browsed read-only if the network is unavailable.
- Books with covers, search/sort, the seven server page-size presets, title and cover-spread settings, and deletion. Page/spread viewer, filmstrip, add/duplicate/remove/reorder pages, rename pages, and layer inspector.
- Touch selection and move, basic resize/rotate and layer ordering, text/photo insertion, a small sticker selection and washi tape, undo/redo across pages, debounced full-document saves, and locally preserved unacknowledged edits. Unmodified JSON fields survive a client edit. Like the web client, concurrent edits from different clients are last-write-wins.
- Photo library, album browsing/creation, adding photos to albums, image details, and foreground uploads from Photos or Files. Image Grid builds an independent PNG contact sheet; it does not mutate books.
- Server export creation, polling, file download and the iPad share sheet. Settings shows the connected account and server runtime.

The [rendering bridge](engine/README.md) runs pinned Zakka editor-core in JavaScriptCore. The client rasterizes its SVG with WebKit rather than the roadmap's resvg XCFramework. The bundled fonts and sticker set are partial; final exports are rendered by the server, not from a screen capture.

The roadmap's advanced photo effects, full decoration and map editors, layout catalog, parity/performance gates, Pencil Pro controls, multiple windows, integrations and TestFlight work are not complete. Uploads are foreground operations; there is no share extension, background upload queue or offline editing mode. The initial client uses a small hand-written API transport and an account-specific JSON metadata cache rather than generated endpoints and SwiftData.

## Development

The Xcode project is checked in; XcodeGen is needed only after adding files or changing target settings (`xcodegen generate`). The local `Packages/ZakkaCore` package owns session/network handling and lossless page-document edits.

```sh
swift test --package-path Packages/ZakkaCore
xcodebuild -project ZakkaPad.xcodeproj -scheme ZakkaPad \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=latest' build
```

The opt-in UI test registers a disposable account on a real server, uploads its own image, signs in through the app and verifies the server-side result of editing. Use a disposable simulator and an isolated Zakka server, with registration enabled:

```sh
TEST_RUNNER_ZAKKA_TEST_SERVER=http://127.0.0.1:8080 \
  xcodebuild -project ZakkaPad.xcodeproj -scheme ZakkaPad \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=latest' \
  -parallel-testing-enabled NO test
```
