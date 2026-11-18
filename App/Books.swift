import SwiftUI
import ZakkaCore

struct BooksView: View {
    @Environment(Studio.self) var studio
    @State private var newBook = false
    @State private var editing: IdentifiedRecord?
    @State private var deleting: IdentifiedRecord?
    @State private var query = ""
    @State private var byName = false
    var books: [JSONValue] { (studio.snapshot?.books ?? []).sorted { byName ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0["updatedAt"].text > $1["updatedAt"].text } }
    var visible: [JSONValue] { books.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) } }

    var body: some View {
        GeometryReader { area in
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    PageHeading(section: "Studio  /  01", title: "Books", subtitle: "Your collection of handmade stories.") {
                        Button { newBook = true } label: { Label("New book", systemImage: "plus") }.buttonStyle(StudioButton()).disabled(!studio.canEdit)
                    }
                    if let featured = books.max(by: { $0["updatedAt"].text < $1["updatedAt"].text }), query.isEmpty {
                        Button { studio.activeBook = featured.id } label: {
                            HStack(spacing: 22) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Eyebrow("On the worktable").foregroundStyle(Palette.leaf)
                                    Text(featured.title).font(.system(size: area.size.width > 600 ? 34 : 24, design: .serif)).lineLimit(2)
                                    Text("\(bookSize(featured))   /   \(Int(featured["pageCount"].double)) pages").font(.caption.monospaced())
                                    Label("Open book", systemImage: "arrow.up.right").font(.caption.weight(.semibold)).padding(.top,3)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                CoverTile(book: featured).frame(width: max(100,min(area.size.width*0.25,220)),height: 145)
                            }.padding(.horizontal, 26).padding(.vertical, 15).frame(maxWidth: .infinity)
                                .background(Palette.board, in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain).accessibilityIdentifier("featured.book")
                    }
                    HStack(spacing: 14) {
                        Eyebrow("Collection  /  \(String(format:"%02d",books.count))")
                        Spacer()
                        HStack(spacing: 6) { Image(systemName: "magnifyingglass"); TextField("Find a book", text: $query).frame(maxWidth: 128) }
                            .font(.caption).foregroundStyle(Palette.muted)
                        Menu {
                            Picker("Sort", selection: $byName) { Text("Recently updated").tag(false); Text("Title").tag(true) }
                        } label: { Image(systemName: "arrow.up.arrow.down") }.accessibilityLabel("Sort books")
                    }
                    Divider().padding(.top,-12)
                    if visible.isEmpty && studio.refreshing { ProgressView().frame(maxWidth: .infinity) }
                    else if visible.isEmpty {
                        EmptyStudio(icon:"books.vertical", title: query.isEmpty ? "An empty shelf" : "No matching books",
                                    message: query.isEmpty ? "Create a book and start with its first page." : "Try searching for another title.")
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: area.size.width < 600 ? 155 : 185), spacing: 20)], alignment: .leading, spacing:22) {
                            ForEach(visible, id: \.id) { book in
                                Button { studio.activeBook = book.id } label: {
                                    VStack(alignment: .leading, spacing: 9) {
                                        CoverTile(book: book).padding(15).frame(maxWidth:.infinity).frame(height: 138)
                                            .background(Palette.side, in: RoundedRectangle(cornerRadius: 10))
                                        Text(book.title).font(.title3).fontDesign(.serif).lineLimit(2)
                                        Text("\(Int(book["pageCount"].double)) pages   ·   \(bookSize(book))").font(.caption).foregroundStyle(Palette.muted)
                                    }.frame(maxWidth:.infinity, alignment:.leading)
                                }.buttonStyle(.plain).contextMenu {
                                    Button("Open book") { studio.activeBook = book.id }
                                    Button("Book settings") { editing = IdentifiedRecord(value:book) }.disabled(!studio.canEdit)
                                    Button("Delete book",role:.destructive) { deleting = IdentifiedRecord(value:book) }.disabled(!studio.canEdit)
                                }
                            }
                        }
                    }
                }.padding(.horizontal, area.size.width < 600 ? 22 : 36).padding(.bottom,32)
                    .frame(maxWidth: 1220).frame(maxWidth:.infinity)
            }.refreshable { await studio.refresh() }
        }
        .sheet(isPresented: $newBook) { BookForm(book: nil) }
        .sheet(item: $editing) { BookForm(book: $0.value) }
        .alert("Delete this book?", isPresented: Binding(get:{deleting != nil},set:{if !$0 { deleting = nil }}), presenting:deleting) { item in
            Button("Delete",role:.destructive) { Task { do { _ = try await studio.mutation("/books/\(item.id)","DELETE"); await studio.refresh() } catch { studio.handle(error) } } }
            Button("Cancel", role:.cancel) {}
        } message: { Text("“\($0.value.title)” will be removed from this server.") }
    }
}

struct IdentifiedRecord: Identifiable {
    let value: JSONValue
    var id: String { value.id }
}

struct CoverTile: View {
    @Environment(Studio.self) var studio
    let book: JSONValue
    var body: some View {
        let aspect = max(1,book["pageWidth"].double)/max(1,book["pageHeight"].double)
        ZStack {
            Color.white
            if let doc = studio.cover(book), let client = studio.client { PageArtwork(document: doc, client: client) }
            else if studio.refreshing { ProgressView() }
            else { Image(systemName: "book.closed").foregroundStyle(Palette.muted) }
        }.aspectRatio(aspect,contentMode:.fit)
            .overlay(alignment:.leading) { Rectangle().fill(.black.opacity(0.07)).frame(width:3) }
            .overlay(Rectangle().stroke(.black.opacity(0.13),lineWidth:0.6))
            .shadow(color:.black.opacity(0.16),radius:3,x:1,y:3)
    }
}

struct BookForm: View {
    @Environment(Studio.self) var studio
    @Environment(\.dismiss) var dismiss
    let book: JSONValue?
    @State private var title = ""
    @State private var preset = 3
    @State private var covers = true
    @State private var busy = false
    @State private var message = ""
    private let sizes = [(2100,2100),(2400,2400),(2400,3000),(2700,2700),(3000,3000),(3300,2550),(3600,3600)]
    var body: some View {
        NavigationStack {
            Form {
                Section("Book details") { TextField("Book title", text:$title).accessibilityIdentifier("book.title") }
                Section("Format") {
                    if book == nil { Picker("Page size",selection:$preset) { ForEach(sizes.indices,id:\.self) { i in
                        Text(bookSize(["pageWidth":.number(Double(sizes[i].0)),"pageHeight":.number(Double(sizes[i].1))])).tag(i)
                    } } }
                    Toggle("Cover spread", isOn:$covers)
                }
                if !message.isEmpty { Text(message).foregroundStyle(.red) }
            }.navigationTitle(book == nil ? "New book" : "Book settings")
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button(book == nil ? "Create" : "Save") { submit() }.disabled(busy || title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) } }
        }.onAppear { title = book?.title ?? ""; covers = book?["coverSpreadEnabled"] != false }
    }
    private func submit() {
        busy = true
        Task {
            defer { busy = false }
            do {
                var body: JSONValue = ["title":.string(title),"coverSpreadEnabled":.bool(covers)]
                if book == nil { body["pageWidth"] = .number(Double(sizes[preset].0)); body["pageHeight"] = .number(Double(sizes[preset].1)) }
                let result = try await studio.mutation(book.map { "/books/\($0.id)" } ?? "/books", book == nil ? "POST":"PATCH",body)
                await studio.refresh(); dismiss()
                if book == nil { studio.activeBook = result.id }
            } catch { message = error.localizedDescription }
        }
    }
}
