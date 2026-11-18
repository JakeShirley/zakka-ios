import Foundation
import WebKit

/// One headless native WebKit SVG renderer, not one web view per grid cell. SVG is decoded
/// as an *image*, never an HTML document. No server URLs, cookies, or page scripts enter it.
@MainActor
final class ArtworkRaster {
    static let shared = ArtworkRaster()
    private let webView: WKWebView

    private init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
    }

    func png(svg: String, images: [String], width: Int, height: Int) async throws -> Data {
        try Task.checkCancellation()
        let result = try await webView.callAsyncJavaScript(
            """
            // Only replace complete image href attributes emitted by the bridge.
            const sized = svg.replace(/^<svg\\b[^>]*>/, root => root
              .replace(/\\bwidth="[^"]*"/, 'width="' + width + '"')
              .replace(/\\bheight="[^"]*"/, 'height="' + height + '"'));
            let size = sized.length;
            const markup = sized.replace(/ href="zakka-media:(\\d+)"/g, (_, i) => {
              const uri = images[+i] || transparentPixel;
              size += uri.length;
              if (size > 48 * 1024 * 1024) throw Error('Page media limit exceeded');
              return ' href="' + uri + '"';
            });
            const img = new Image();
            const url = URL.createObjectURL(new Blob([markup], { type: 'image/svg+xml' }));
            const canvas = document.createElement('canvas');
            try {
              img.src = url;
              await img.decode();
              canvas.width = width;
              canvas.height = height;
              canvas.getContext('2d').drawImage(img, 0, 0, width, height);
              return canvas.toDataURL('image/png').split(',')[1];
            } finally {
              URL.revokeObjectURL(url);
              canvas.width = canvas.height = 0;
            }
            """,
            arguments: [
                "svg": svg, "images": images, "width": width, "height": height,
                "transparentPixel": "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxIiBoZWlnaHQ9IjEiLz4=",
            ], in: nil, contentWorld: .defaultClient
        )
        try Task.checkCancellation()
        guard let encoded = result as? String, let data = Data(base64Encoded: encoded), !data.isEmpty else {
            throw CocoaError(.coderReadCorrupt)
        }
        return data
    }
}
