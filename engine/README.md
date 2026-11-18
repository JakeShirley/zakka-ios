# Native page artwork

`PageArtwork(document:client:)` displays a noninteractive page at its canvas aspect ratio. For explicit control, pass `tier: .thumbnail` (covers/filmstrip) or `.editor` (preview assets, editor placeholders). The default chooses by available size. Supply the page's **document**, not the response envelope. Layer selection, zoom, mutation and the surrounding chrome belong to the caller.

The app ships `App/Rendering/ZakkaArtwork.bundle` and links the local `Packages/ZakkaRaster` Swift package. A clean app build needs neither Node, Rust, nor a server checkout. `Acknowledgements.txt`, `Resvg-LICENSES.txt` and `Rust-LICENSE.html` in the bundle carry the redistribution notices.

## Rebuild or update

From `engine/` with Git and Node 24.3+:

```sh
npm ci
npm run build
npm test
# With Xcode 27 and a booted iPad simulator:
bash tests/native-smoke.sh
```

`build.mjs` fetches the exact upstream Zakka commit into an ignored build directory. Alternatively set `ZAKKA_SOURCE` to an existing Git checkout containing that commit; it is only read via `git archive`. No local dirty changes, generated backend files, global npm modules, or absolute paths are inputs. When updating the commit and npm lock, regenerate the **entire** `.bundle` including license notices and run both test suites. XcodeGen discovers the bundle under `App` without a build script.

To rebuild the static XCFramework, run `bash Packages/ZakkaRaster/build.sh` from the repository root with Xcode 27, Node and rustup installed. The script downloads the checksum-pinned **resvg 0.45.1** release, uses Rust **1.91.1**, the upstream `Cargo.lock`, size-optimized LTO, and the `text`, `raster-images`, `system-fonts` features (the upstream C API needs the latter to compile; the app does not scan fonts). It builds `aarch64-apple-ios`, `aarch64-apple-ios-sim`, and `x86_64-apple-ios`, strips local symbols, packages the original C header + module map and regenerates the Rust/third-party notices. The one source patch disables filesystem image references. For pinned output use the same Xcode/SDK (built with SDK 27.2); normal app builds use the shipped slices. The smoke script links the packaged simulator slice without building the app, verifies real NASA JPEG pixels against a separate ImageIO reference and checks both text paths. Its output is `engine/.build/nativepkg/photo-text.png`.

## What renders

* One serial JavaScriptCore host runs the pinned upstream `renderPageDocumentSvg`, Zod defaults, photo crops/filters/frames, markdown text layout, masks, sticker/washi geometry, backgrounds and map code. A render returns SVG with indexed image references plus a deduplicated media manifest. App code does not write normalized documents back.
* `ZakkaClient` alone reads authenticated bytes. Photo rows are fetched for the server-provided thumbnail/preview variant URLs; ImageIO orients and downsamples original/legacy formats when needed. Custom photo tapes, custom stickers/backgrounds, built-in textures and proxied map tiles use their actual API paths.
* A serial actor calls the **resvg C API** to parse SVG with embedded images and render premultiplied RGBA pixels at the requested size; ImageIO encodes the result. The reusable font database loads bundled Lato/Baskervville TTFs losslessly unpacked from upstream WOFF. There is no WebKit dependency or remote page.
* Bounded client-scoped memory caches hold media and complete previews. Document changes cancel/supersede prior requests; missing media or an unrecognized layer leaves the rest visible with a retry indicator. Invalid canvases or unsupported document versions show an error rather than rendering a different page.

## Fidelity and limits

This is a display preview, not a print/export substitute. Thumbnails are capped at 640 pixels, editor pages at 2048. Photos are downsampled further for pages containing many assets. Two render jobs and three concurrent media requests per job are allowed. There is no persistent media or layer-tile cache here.

The bundle includes Natural Earth 1:50m geography (also used for zoomed-in maps), selected upstream open-source WOFF substitutes with 20 font aliases, and 36 commonly used Noto/Twemoji SVGs. Other catalog stickers use the Unicode mapping and a CoreText system-emoji raster; other fonts use the bundled fontdb fallback. No commercial fonts, full emoji catalogs, background images, or Shutterfly layout collections are embedded. Font coverage, wrapping and some filter/emoji rendering can differ from server Sharp/librsvg. The smoke tests verify embedded-image pixels and the editor-core contract, not full pixel parity with exports.
