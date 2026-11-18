import SwiftUI
import UIKit
import ZakkaCore

enum ArtworkTier { case automatic, thumbnail, editor }

struct PageArtwork: View {
    let document: JSONValue
    let client: ZakkaClient
    var tier: ArtworkTier = .automatic
    @Environment(\.displayScale) private var displayScale
    @State private var displayed: Request?
    @State private var image: UIImage?
    @State private var missing = 0
    @State private var attempt = 0

    private struct Request: Equatable {
        let document: JSONValue
        let client: ObjectIdentifier
        let width, height: Int
        let editor, thumbnail: Bool
        let attempt: Int
    }

    init(document: JSONValue, client: ZakkaClient, tier: ArtworkTier = .automatic) {
        self.document = document
        self.client = client
        self.tier = tier
    }

    private var aspect: CGFloat {
        let canvas = document["canvas"]
        let width = canvas["width"].double, height = canvas["height"].double
        guard width >= 320, height >= 320, width <= 10_000, height <= 10_000 else { return 1 }
        return width / height
    }

    var body: some View {
        Rectangle().fill(Color.white)
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    let longest = max(geo.size.width, geo.size.height)
                    let thumb = tier == .thumbnail || (tier == .automatic && longest < 360)
                    let edge = min(thumb ? 640 : 2048, max(32, ceil(longest * displayScale / 32) * 32))
                    let req = Request(document: document, client: ObjectIdentifier(client),
                                      width: max(1, Int((edge * min(1, aspect)).rounded())),
                                      height: max(1, Int((edge / max(1, aspect)).rounded())),
                                      editor: tier == .editor || (tier == .automatic && !thumb), thumbnail: thumb,
                                      attempt: attempt)
                    ZStack {
                        if displayed == req, let image {
                            Image(uiImage: image).resizable().interpolation(.high)
                        }
                        if displayed == req, missing > 0 {
                            Button {
                                attempt += 1
                            } label: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.secondary).padding(4)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .accessibilityLabel("Page preview incomplete. Retry")
                        } else if displayed != req {
                            ProgressView().controlSize(.mini)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .task(id: req) {
                        guard longest > 0 else { return }
                        do {
                            let result = try await ArtworkPipeline.shared.render(
                                document: document, client: client, width: req.width, height: req.height,
                                editor: req.editor, thumbnail: req.thumbnail)
                            try Task.checkCancellation()
                            guard let ready = UIImage(data: result.png) else { throw ArtworkError.imageUnavailable }
                            image = ready
                            missing = result.missing
                            displayed = req
                        } catch {
                            if !Task.isCancelled {
                                image = nil
                                missing = 1
                                displayed = req
                            }
                        }
                    }
                }
            }
            .clipped()
            .accessibilityLabel("Page artwork")
    }
}
