import SwiftUI
import ZakkaCore

/// A client-side contact sheet; the original assets and books are untouched.
struct GridView: View {
    @Environment(Studio.self) var studio
    @State private var ids: [String] = []
    @State private var count = 3
    @State private var gap = 10
    @State private var dark = false
    @State private var choosing = false
    @State private var rendering = false
    @State private var output: URL?
    private var photos: [JSONValue] { ids.compactMap { id in studio.snapshot?.photos.first { $0.id == id } } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(section: "Studio  /  03", title: "Image grid", subtitle: "Compose a contact sheet from your library. Your originals stay untouched.") {
                    Button { choosing = true } label: { Label("Choose photos", systemImage: "photo.on.rectangle") }.buttonStyle(StudioButton())
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { controls }
                    VStack(alignment: .leading) { controls }
                }
                if photos.isEmpty {
                    EmptyStudio(icon: "square.grid.3x3", title: "A blank contact sheet", message: "Choose up to 24 photos, in the order you want them to appear.")
                } else if let client = studio.client {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: CGFloat(gap)), count: count), spacing: CGFloat(gap)) {
                        ForEach(photos, id: \.id) { a in
                            AssetImage(asset: a, client: client).aspectRatio(1, contentMode: .fit)
                                .accessibilityLabel(a["originalFilename"].text)
                        }
                    }.padding(CGFloat(gap)).background(dark ? Color.black : Color.white)
                        .overlay(Rectangle().stroke(Palette.line))
                    HStack {
                        Button { Task { await export() } } label: { Label("Render PNG", systemImage: "arrow.down.doc") }
                            .buttonStyle(StudioButton()).disabled(rendering)
                        if rendering { ProgressView() }
                        if let output { ShareLink(item: output) { Label("Share grid", systemImage:"square.and.arrow.up") } }
                    }
                }
            }.padding(.horizontal,30).padding(.bottom,30)
        }.onChange(of:ids) { _,_ in output = nil }.onChange(of:count) { _,_ in output = nil }
            .onChange(of:gap) { _,_ in output = nil }.onChange(of:dark) { _,_ in output = nil }
            .sheet(isPresented:$choosing) {
                NavigationStack {
                    ScrollView {
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:120))]) {
                            if let client = studio.client {
                                ForEach(studio.snapshot?.photos ?? [],id:\.id) { a in
                                    Button {
                                        if let i = ids.firstIndex(of:a.id) { ids.remove(at:i) }
                                        else if ids.count < 24 { ids.append(a.id) }
                                    } label: {
                                        AssetImage(asset:a,client:client).aspectRatio(1.35,contentMode:.fit)
                                            .overlay(alignment:.topTrailing) {
                                                if let i = ids.firstIndex(of:a.id) { Text("\(i+1)").font(.caption.bold()).padding(6).background(Palette.leaf,in:Circle()).foregroundStyle(.white).padding(5) }
                                            }
                                    }.accessibilityLabel(a["originalFilename"].text)
                                }
                            }
                        }.padding()
                    }.navigationTitle("Choose photos").toolbar { Button("Done") { choosing = false } }
                }
            }
    }
    @ViewBuilder private var controls: some View {
        Picker("Columns",selection:$count) { ForEach(1...6,id:\.self) { Text("\($0) columns").tag($0) } }
        Picker("Gutter",selection:$gap) { ForEach([0,5,10,20],id:\.self) { Text("\($0) pt gutter").tag($0) } }
        Toggle("Dark paper",isOn:$dark).fixedSize()
    }
    private func export() async {
        guard let c = studio.client else { return }
        let selection = photos, columns = count, gutter = gap * 2, black = dark
        rendering = true; defer { rendering = false }
        do {
            let cell = 360, rows = (selection.count + columns - 1) / columns
            let size = CGSize(width:columns*cell+(columns+1)*gutter,height:rows*cell+(rows+1)*gutter)
            // Decode no more than one 360px thumbnail per grid slot, never the originals as one large batch.
            var images: [UIImage] = []
            for a in selection {
                let path = a["thumbnailUrl"].text
                guard !path.isEmpty,let img = UIImage(data:try await c.data(path)) else { throw ClientError.response }
                images.append(img)
            }
            let f = UIGraphicsImageRendererFormat();f.scale = 1;f.opaque = true
            let data = UIGraphicsImageRenderer(size:size,format:f).pngData { r in
                (black ? UIColor.black:UIColor.white).setFill();r.fill(CGRect(origin:.zero,size:size))
                for (i,img) in images.enumerated() {
                    let rect = CGRect(x:gutter+(i%columns)*(cell+gutter),y:gutter+(i/columns)*(cell+gutter),width:cell,height:cell)
                    let scale = max(rect.width/img.size.width,rect.height/img.size.height)
                    let w = img.size.width*scale,h = img.size.height*scale
                    r.cgContext.saveGState();r.cgContext.clip(to:rect)
                    img.draw(in:CGRect(x:rect.midX-w/2,y:rect.midY-h/2,width:w,height:h))
                    r.cgContext.restoreGState()
                }
            }
            let url = URL.temporaryDirectory.appending(path:"Zakka-grid-\(UUID().uuidString.prefix(8)).png")
            try data.write(to:url)
            if selection.map(\.id) == ids,count == columns,gap*2 == gutter,dark == black { output = url }
        } catch { studio.handle(error) }
    }
}
