# Native page artwork

`PageArtwork(document:client:)` displays a noninteractive page at its canvas aspect ratio. For explicit control, pass `tier: .thumbnail` (covers/filmstrip) or `.editor` (preview assets, editor placeholders). The default chooses by available size. Supply the page's **document**, not the response envelope. Layer selection, zoom, mutation and the surrounding chrome belong to the caller.

The app ships `App/Rendering/ZakkaArtwork.bundle` as a single resource; a clean app build needs neither Node, Rust, nor a server checkout. The `Acknowledgements.txt` inside is suitable for the app's acknowledgements screen.

## Rebuild or update

From `engine/` with Git and Node 24.3+:

```sh
npm ci
npm run build
npm test
bash tests/native-smoke.sh
# With Xcode 27 and a booted iPad simulator:
bash tests/native-smoke.sh simulator
```

`build.mjs` fetches the exact upstream Zakka commit into an ignored build directory. Alternatively set `ZAKKA_SOURCE` to an existing Git checkout containing that commit; it is only read via `git archive`. No local dirty changes, generated backend files, global npm modules, or absolute paths are inputs. When updating the commit and npm lock, regenerate the **entire** `.bundle` including license notices and run both test suites. XcodeGen discovers the bundle under `App` without a build script.

## What renders

* One serial JavaScriptCore host runs the pinned upstream `renderPageDocumentSvg`, Zod defaults, photo crops/filters/frames, markdown text layout, masks, sticker/washi geometry, backgrounds and map code. A render returns SVG with indexed image references plus a deduplicated media manifest. App code does not write normalized documents back.
* `ZakkaClient` alone reads authenticated bytes. Photo rows are fetched for the server-provided thumbnail/preview variant URLs; ImageIO orients and downsamples original/legacy formats when needed. Custom photo tapes, custom stickers/backgrounds, built-in textures and proxied map tiles use their actual API paths.
* A single isolated, nonpersistent **native WebKit SVG image decoder** draws to a bounded canvas and returns a PNG. It receives data images, never server credentials, HTML from the server, or a remote page. Using the platform SVG renderer instead of embedding a resvg binary supports browser SVG filters, nested SVGs, text and patterns without a Rust toolchain or one web view per page. SwiftUI displays only the finished native image.
* Bounded client-scoped memory caches hold media and complete previews. Document changes cancel/supersede prior requests; missing media or an unrecognized layer leaves the rest visible with a retry indicator. Invalid canvases or unsupported document versions show an error rather than rendering a different page.

## Fidelity and limits

This is a display preview, not a print/export substitute. Thumbnails are capped at 640 pixels, editor pages at 2048. Photos are downsampled further for pages containing many assets. Two render jobs and three concurrent media requests per job are allowed. There is no persistent media or layer-tile cache here.

The bundle includes Natural Earth 1:50m geography (also used for zoomed-in maps), selected upstream open-source WOFF substitutes with 20 font aliases, and 36 commonly used Noto/Twemoji SVGs. Other catalog stickers use the Unicode mapping and system emoji; other fonts use the platform fallback. No commercial fonts, full emoji catalogs, background images, or Shutterfly layout collections are embedded. Text wrapping for system fonts and some filter/emoji rendering can differ from server Sharp/librsvg. The smoke tests verify embedded-image pixels and the editor-core contract, not full pixel parity with exports.
