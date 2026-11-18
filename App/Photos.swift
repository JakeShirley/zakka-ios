import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import ZakkaCore

struct AssetImage: View {
    let asset: JSONValue
    let client: ZakkaClient
    var preview = false
    var fit = false
    @State private var image: UIImage?
    @State private var failed = false
    var path: String {
        if preview, let variant = asset["variants"].items.first(where: {$0["kind"] == "preview"}) { return variant["contentUrl"].text }
        if !asset["thumbnailUrl"].text.isEmpty { return asset["thumbnailUrl"].text }
        return asset["originalContentUrl"].text
    }
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Palette.side
                if let image { Image(uiImage:image).resizable().aspectRatio(contentMode:fit ? .fit:.fill) }
                else if failed { Image(systemName:"photo.badge.exclamationmark").accessibilityLabel("Image unavailable") }
                else { ProgressView() }
            }.frame(width:geo.size.width,height:geo.size.height).clipped()
        }.task(id:path) {
            image = nil; failed = false
            do {
                let bytes = try await client.data(path)
                guard !Task.isCancelled else { return }
                let decoded = UIImage(data: bytes)
                image = decoded; failed = decoded == nil
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}

struct PhotosView: View {
    @Environment(Studio.self) var studio
    @State private var album: String?
    @State private var albumPhotos: [JSONValue] = []
    @State private var detail: IdentifiedRecord?
    @State private var search = ""
    @State private var files = false
    @State private var picker = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var newAlbum = false
    @State private var albumName = ""
    @State private var albumRevision = 0
    var photos: [JSONValue] {
        (album == nil ? studio.snapshot?.photos ?? [] : albumPhotos).filter { search.isEmpty || $0["originalFilename"].text.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                PageHeading(section:"Studio  /  02",title:"Photos",subtitle:"Source material for your next page.") {
                    Menu {
                        Button("Choose from Photos",systemImage:"photo.on.rectangle") { picker = true }
                        Button("Import from Files",systemImage:"folder") { files = true }
                        Divider()
                        Button("New album",systemImage:"rectangle.stack.badge.plus") { newAlbum = true }
                    } label: { Label("Import",systemImage:"plus").font(.subheadline.weight(.semibold)).padding(.horizontal,16).padding(.vertical,10).background(Palette.leaf,in:Capsule()).foregroundStyle(.white) }
                        .disabled(!studio.canEdit || importing)
                }
                ScrollView(.horizontal) {
                    HStack { chip("All photos",id:nil)
                        ForEach(studio.snapshot?.albums ?? [],id:\.id) { group in chip(group.title,id:group.id).disabled(studio.offline) }
                    }
                }.scrollIndicators(.hidden)
                HStack {
                    Eyebrow("Photo index  /  \(String(format:"%02d",photos.count))")
                    Spacer()
                    if importing { ProgressView().accessibilityLabel("Importing photos") }
                    Image(systemName:"magnifyingglass")
                    TextField("Find a photo",text:$search).font(.caption).frame(maxWidth:120)
                }
                Divider().padding(.top,-12)
                if let client = studio.client, !photos.isEmpty {
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:170),spacing:15)],alignment:.leading,spacing:18) {
                        ForEach(photos,id:\.id) { photo in
                            Button { detail = IdentifiedRecord(value:photo) } label: {
                                VStack(alignment:.leading,spacing:7) {
                                    AssetImage(asset:photo,client:client).aspectRatio(1.34,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:8))
                                    Text(photo["originalFilename"].text).font(.subheadline.weight(.medium)).lineLimit(1)
                                    Text("\(Int(photo["width"].double)) × \(Int(photo["height"].double))").font(.caption2.monospaced()).foregroundStyle(Palette.muted)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                } else { EmptyStudio(icon:"photo.stack",title:"No photos here yet",message:"Import a photo or choose a different album.") }
            }.padding(.horizontal,30).padding(.bottom,28)
        }.refreshable { await studio.refresh(); albumRevision += 1 }
        .task(id:"\(album ?? ""):\(albumRevision)") {
            albumPhotos = []
            guard let album, let client = studio.client else { return }
            do { let result = try await client.json("/albums/\(album)/assets"); if !Task.isCancelled { albumPhotos = result["assets"].items } } catch { studio.handle(error) }
        }
        .alert("New album",isPresented:$newAlbum) {
            TextField("Album title",text:$albumName)
            Button("Create") { Task { do {
                let r = try await studio.mutation("/albums","POST",["title":.string(albumName)]); albumName = ""; await studio.refresh(); album = r.id
            } catch { studio.handle(error) } } }.disabled(albumName.isEmpty)
            Button("Cancel",role:.cancel) {}
        }
        .sheet(item:$detail,onDismiss:{albumRevision += 1}) { item in PhotoDetail(asset:item.value) }
        .photosPicker(isPresented:$picker,selection:$picked,maxSelectionCount:12,matching:.images)
        .onChange(of:picked) { _, value in
            guard !value.isEmpty else { return }
            Task { await uploadPicked(value); picked = [] }
        }
        .fileImporter(isPresented:$files,allowedContentTypes:[.image],allowsMultipleSelection:true) { result in
            Task {
                importing = true; defer { importing = false }
                do {
                    for url in try result.get() {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let values = try url.resourceValues(forKeys:[.fileSizeKey,.contentTypeKey])
                        guard (values.fileSize ?? 0) <= 20*1024*1024 else { throw ClientError.http(413,"Choose an image smaller than 20 MiB.") }
                        try await upload(try Data(contentsOf:url),name:url.lastPathComponent,type:values.contentType ?? .image)
                    }
                } catch { if (error as NSError).code != NSUserCancelledError { studio.handle(error) } }
                await studio.refresh(); albumRevision += 1
            }
        }
    }
    private func chip(_ title:String,id:String?) -> some View {
        Button { album = id } label: {
            Text(title).font(.caption.weight(.semibold)).padding(.horizontal,14).padding(.vertical,8)
                .background(album == id ? Palette.leaf : Palette.side,in:Capsule()).foregroundStyle(album == id ? .white:Palette.muted)
        }.buttonStyle(.plain)
    }
    private func upload(_ data:Data,name:String,type:UTType) async throws {
        guard let client = studio.client,studio.canEdit else { throw URLError(.notConnectedToInternet) }
        let a = try await client.upload(data,filename:name,mime:type.preferredMIMEType ?? "application/octet-stream")
        if let album { _ = try await studio.mutation("/albums/\(album)/assets","POST",["assetIds":[.string(a.id)]]) }
    }
    private func uploadPicked(_ selection:[PhotosPickerItem]) async {
        importing = true; defer { importing = false }
        do {
            for item in selection {
                guard let d = try await item.loadTransferable(type:Data.self) else { throw ClientError.response }
                let type = item.supportedContentTypes.first ?? .jpeg
                try await upload(d,name:"Photo-\(UUID().uuidString.prefix(8)).\(type.preferredFilenameExtension ?? "jpg")",type:type)
            }
        } catch { studio.handle(error) }
        await studio.refresh(); albumRevision += 1
    }
}

private struct PhotoDetail: View {
    @Environment(Studio.self) var studio
    @Environment(\.dismiss) var dismiss
    let asset: JSONValue
    @State private var message = ""
    var body: some View {
        NavigationStack {
            VStack(alignment:.leading,spacing:14) {
                if let client = studio.client { AssetImage(asset:asset,client:client,preview:true,fit:true).clipShape(RoundedRectangle(cornerRadius:10)) }
                Eyebrow("Library  /  Photo details")
                Text(asset["originalFilename"].text).font(.title2).fontDesign(.serif)
                Text("\(Int(asset["width"].double)) × \(Int(asset["height"].double)) px   ·   \(ByteCountFormatter.string(fromByteCount:Int64(asset["byteSize"].double),countStyle:.file))")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                if let albums = studio.snapshot?.albums,!albums.isEmpty {
                    Menu("Add to album") { ForEach(albums,id:\.id) { album in Button(album.title) { Task { do {
                        _ = try await studio.mutation("/albums/\(album.id)/assets","POST",["assetIds":[.string(asset.id)]])
                        message = "Added to \(album.title)"; await studio.refresh()
                    } catch { message = error.localizedDescription } } } } }.disabled(!studio.canEdit)
                }
                if !message.isEmpty { Text(message).font(.footnote) }
            }.padding(24).background(Palette.paper).navigationTitle("Photo info").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }
        }
    }
}
