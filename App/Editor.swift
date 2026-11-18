import SwiftUI
import ZakkaCore

private struct EditStep { let page: String, before: JSONValue, after: JSONValue }
private enum EditorSheet: String, Identifiable {
    case text, photo, export, settings, pageTitle, editText, inspector
    var id: String { rawValue }
}

struct EditorView: View {
    @Environment(Studio.self) var studio
    let bookID: String
    @State private var pageID = ""
    @State private var selected: String?
    @State private var spread = false
    @State private var inspector = true
    @State private var sheet: EditorSheet?
    @State private var message: String?
    @State private var removePage = false
    @State private var working = false
    @State private var history: [EditStep] = []
    @State private var future: [EditStep] = []
    private var book: JSONValue { studio.snapshot?.details[bookID] ?? .null }
    private var pageIDs: [String] { book["pages"].items.map { $0["pageId"].text } }
    private var page: JSONValue { studio.snapshot?.pages[pageID] ?? .null }
    private var document: JSONValue { page["document"] }
    private var layers: [JSONValue] { document["layers"].items }
    private var layer: JSONValue? { layers.first { $0.id == selected } }
    private var pageNumber: Int { (pageIDs.firstIndex(of:pageID) ?? 0) + 1 }
    private var shown: [String] {
        guard spread, let pair = book["spreads"].items.first(where:{ $0["pageIds"].items.contains(.string(pageID)) }) else { return pageID.isEmpty ? [] : [pageID] }
        return [pair["leftPageId"].text, pair["rightPageId"].text].filter { !$0.isEmpty }
    }
    var body: some View {
        GeometryReader { geo in
            VStack(spacing:0) {
                header(compact:geo.size.width < 850, inspectorFits:geo.size.width >= 780)
                Divider()
                HStack(spacing:0) {
                    VStack(alignment:.leading,spacing:0) {
                        HStack {
                            Eyebrow(spread ? "Workspace  /  Spread" : "Workspace  /  Page \(String(format:"%02d",pageNumber))")
                            Spacer()
                            Text(bookSize(book)).font(.caption.monospaced())
                        }.foregroundStyle(Palette.muted).padding(.horizontal,24).padding(.vertical,14)
                        HStack(spacing:spread ? 2 : 0) {
                            ForEach(shown,id:\.self) { id in
                                let doc = studio.snapshot?.pages[id]?["document"] ?? .null
                                if doc != .null, let c = studio.client {
                                    EditablePage(document:doc,client:c,selected:id == pageID && !spread ? selected : nil, editable:studio.canEdit && !spread,
                                                 choose:{ picked in pageID = id; selected = picked },
                                                 move:{ picked,dx,dy in changeLayer(picked) { value in
                                                     value["x"] = .number(value["x"].double + dx)
                                                     value["y"] = .number(value["y"].double + dy)
                                                 } })
                                } else { ProgressView().frame(maxWidth:.infinity,maxHeight:.infinity) }
                            }
                            if shown.isEmpty { EmptyStudio(icon:"doc",title:working ? "Opening book…" : "No pages",message:"Add a page from the filmstrip.") }
                        }.padding(.horizontal,26).padding(.vertical,10).frame(maxWidth:.infinity,maxHeight:.infinity)
                        HStack {
                            Image(systemName:spread ? "book.pages":"doc")
                            Text(spread ? shown.compactMap{ studio.snapshot?.pages[$0]?.title }.joined(separator:"  /  ") : page.title)
                            Spacer(); Text("\(pageNumber) / \(pageIDs.count)").monospacedDigit()
                        }.font(.caption).foregroundStyle(Palette.muted).padding(.horizontal,24).padding(.vertical,12)
                    }.background(Palette.board)
                    if inspector && !spread && geo.size.width >= 780 {
                        Divider(); inspectorView.frame(width:geo.size.width > 1050 ? 240 : 202)
                    }
                }
                Divider(); filmstrip
            }.background(Palette.paper).foregroundStyle(Palette.ink)
        }.task { await load() }
        .sheet(item:$sheet) { which in
            switch which {
            case .text: TextEntry(title:"Add text",initial:"",action:"Add text") { value in add("text",value) }
            case .editText: TextEntry(title:"Edit text",initial:layer?["text"].text ?? "",action:"Save") { text in
                if let selected { changeLayer(selected) { $0["text"] = .string(text) } }
            }
            case .photo: AssetPicker { a in add("photo",a.id) }
            case .export: ExportView(book:book,page:page)
            case .settings: BookForm(book:book)
            case .inspector:
                NavigationStack {
                    inspectorView.navigationTitle("Layer inspector").navigationBarTitleDisplayMode(.inline)
                        .toolbar { Button("Done") { sheet = nil } }
                }.presentationDetents([.medium, .large])
            case .pageTitle: TextEntry(title:"Page title",initial:page.title,action:"Save") { title in
                action { _ = try await studio.mutation("/pages/\(pageID)","PATCH",["title":.string(title)]); await load() }
            }
            }
        }
        .alert("Editor",isPresented:Binding(get:{ message != nil || studio.error != nil },set:{ if !$0 { message = nil; studio.error = nil } })) {
            Button("OK") { message = nil; studio.error = nil }
        } message: { Text(message ?? studio.error ?? "") }
        .confirmationDialog("Remove this page from the book?",isPresented:$removePage,titleVisibility:.visible) {
            Button("Remove page",role:.destructive) { setOrder(pageIDs.filter{$0 != pageID}, select:nil) }
        }
    }
    private func header(compact:Bool, inspectorFits:Bool) -> some View {
        HStack(spacing: compact ? 9 : 18) {
            Button { studio.activeBook = nil; Task { await studio.refresh() } } label: { Image(systemName:"chevron.left").frame(width:30,height:38) }.accessibilityLabel("Back to Books")
            VStack(alignment:.leading,spacing:2) {
                Eyebrow("Book editor",size:9).foregroundStyle(Palette.rust)
                Text(book.title).font(.system(size:compact ? 19 : 23,design:.serif)).lineLimit(1)
            }
            Spacer()
            Picker("View mode",selection:$spread) {
                Text("Page").tag(false); Text("Spread").tag(true)
            }.pickerStyle(.segmented).frame(maxWidth:145).onChange(of:spread) { _,_ in selected = nil }
            Button { undo() } label:{Image(systemName:"arrow.uturn.backward")}.disabled(history.isEmpty || !studio.canEdit).keyboardShortcut("z").accessibilityLabel("Undo")
            Button { redo() } label:{Image(systemName:"arrow.uturn.forward")}.disabled(future.isEmpty || !studio.canEdit).keyboardShortcut("z",modifiers:[.command,.shift]).accessibilityLabel("Redo")
            Menu {
                Button("Photo",systemImage:"photo"){sheet = .photo}
                Button("Text",systemImage:"textformat"){sheet = .text}
                Button("Washi tape",systemImage:"bandage"){add("washiTape","")}
                Menu("Sticker") {
                    Button("Red heart"){add("sticker","noto:red-heart")}
                    Button("Sunflower"){add("sticker","noto:sunflower")}
                    Button("Sparkles"){add("sticker","noto:sparkles")}
                }
            } label:{ Label("Add",systemImage:"plus").font(.subheadline.weight(.semibold)) }
            .accessibilityLabel("Add layer").disabled(!studio.canEdit || document == .null || layers.count >= 200)
            Button { sheet = .export } label:{Image(systemName:"square.and.arrow.up")}.accessibilityLabel("Export book or page").keyboardShortcut("e").disabled(!studio.canEdit || pageID.isEmpty)
            Menu {
                Button(inspectorFits && inspector ? "Hide inspector":"Show inspector",systemImage:"sidebar.right"){
                    if inspectorFits { inspector.toggle() } else { sheet = .inspector }
                }.disabled(spread)
                Button("Book settings",systemImage:"book"){sheet = .settings}.disabled(!studio.canEdit)
                Button("Rename page",systemImage:"pencil"){sheet = .pageTitle}.disabled(!studio.canEdit || pageID.isEmpty)
                Divider()
                Button("Move page earlier",systemImage:"arrow.left"){movePage(pageID,by:-1)}.disabled(!studio.canEdit || pageNumber <= 1)
                Button("Move page later",systemImage:"arrow.right"){movePage(pageID,by:1)}.disabled(!studio.canEdit || pageNumber >= pageIDs.count)
                if !studio.dirtyPages.isEmpty { Button("Retry save"){action{try await studio.flush()}} }
            } label:{Image(systemName:"ellipsis.circle")}.accessibilityLabel("Editor options")
        }.padding(.horizontal,16).padding(.vertical,8).background(Palette.paper)
    }
    private var filmstrip: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Eyebrow("Filmstrip  /  \(String(format:"%02d",pageIDs.count)) pages")
                Spacer()
                Label(studio.offline ? "Offline · read-only" : studio.dirtyPages.isEmpty ? "Saved to server" : "Changes pending",
                      systemImage:studio.offline ? "wifi.slash" : studio.dirtyPages.isEmpty ? "checkmark.circle" : "arrow.triangle.2.circlepath")
                .font(.caption).foregroundStyle(Palette.leaf)
            }
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(alignment:.top,spacing:12) {
                        ForEach(Array(pageIDs.enumerated()),id:\.element) { index,id in
                            Button { selectPage(id) } label:{
                                VStack(alignment:.leading,spacing:4) {
                                    ZStack {
                                        Palette.side
                                        if let c = studio.client, let p = studio.snapshot?.pages[id] {
                                            PageArtwork(document:p["document"],client:c)
                                        } else { Image(systemName:"doc").font(.caption) }
                                    }.frame(width:68,height:46).overlay(Rectangle().stroke(shown.contains(id) ? Palette.leaf : Palette.line,lineWidth:shown.contains(id) ? 2.5:1))
                                    Text(String(format:"%02d",index+1)).font(.caption2.monospacedDigit()).foregroundStyle(shown.contains(id) ? Palette.leaf:Palette.muted)
                                }
                            }.buttonStyle(.plain).accessibilityLabel("Page \(index+1)").accessibilityIdentifier("film.\(index+1)").id(id)
                            .contextMenu {
                                Button("Move earlier"){movePage(id,by:-1)}.disabled(index == 0 || !studio.canEdit)
                                Button("Move later"){movePage(id,by:1)}.disabled(index == pageIDs.count-1 || !studio.canEdit)
                                Button("Duplicate page"){createPage(copy:id)}.disabled(!studio.canEdit || pageIDs.count >= 240)
                                Button("Remove from book",role:.destructive){selectPage(id);removePage = true}.disabled(!studio.canEdit)
                            }
                            .draggable(id)
                            .dropDestination(for:String.self) { ids,_ in
                                guard studio.canEdit,let moving = ids.first,let pos = pageIDs.firstIndex(of:moving),pos != index else{return false}
                                var order = pageIDs;order.remove(at:pos);order.insert(moving,at:index);setOrder(order,select:moving);return true
                            }
                        }
                        Button { createPage(copy:nil) } label:{Image(systemName:"plus").frame(width:52,height:46).background(Palette.side,in:RoundedRectangle(cornerRadius:4))}
                            .buttonStyle(.plain).accessibilityLabel("Add page").disabled(!studio.canEdit || working || pageIDs.count >= 240)
                    }.padding(2)
                }.scrollIndicators(.hidden).onChange(of:pageID){ _,id in reader.scrollTo(id) }
            }
        }.padding(.horizontal,24).padding(.vertical,10)
    }
    private var inspectorView: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Eyebrow("Inspector").foregroundStyle(Palette.rust)
                Text(layer.map { layerName($0) } ?? "Page details").font(.title2).fontDesign(.serif)
                if let layer {
                    let locked = layer["locked"] == true
                    if locked { Label("Locked",systemImage:"lock").font(.caption) }
                    Group {
                        if layer["kind"] == "text" { Button("Edit text",systemImage:"pencil"){sheet = .editText} }
                        HStack { Button("Smaller",systemImage:"minus.magnifyingglass") { scale(0.9) }.labelStyle(.iconOnly)
                            Button("Larger",systemImage:"plus.magnifyingglass") { scale(1.1) }.labelStyle(.iconOnly)
                            Button("Rotate left",systemImage:"rotate.left"){rotate(-5)}.labelStyle(.iconOnly)
                            Button("Rotate right",systemImage:"rotate.right"){rotate(5)}.labelStyle(.iconOnly)
                        }.buttonStyle(.bordered)
                        Menu("Layer actions") {
                            Button("Bring forward"){reorderLayer(1)}
                            Button("Send backward"){reorderLayer(-1)}
                            Button("Duplicate layer"){duplicateLayer()}.disabled(layers.count >= 200)
                            Button("Delete layer",role:.destructive){deleteLayer()}
                        }
                    }.disabled(locked || !studio.canEdit)
                } else {
                    Text(page.title).font(.headline)
                    Text("\(Int(document["canvas"]["width"].double)) × \(Int(document["canvas"]["height"].double)) units").font(.caption.monospaced()).foregroundStyle(Palette.muted)
                    Text("Select a layer on the page or in the list below.").font(.caption).foregroundStyle(Palette.muted)
                }
                Divider(); Eyebrow("Layers  /  \(String(format:"%02d",layers.count))")
                if layers.isEmpty { Text("Add a photo or text to begin.").font(.caption).foregroundStyle(Palette.muted) }
                ForEach(layers.reversed(),id:\.id) { l in
                    Button { selected = l.id } label:{
                        HStack(spacing:8) {
                            Image(systemName:layerIcon(l)).frame(width:24)
                            VStack(alignment:.leading,spacing:2) {
                                Text(layerName(l)).font(.subheadline.weight(.medium)).lineLimit(1)
                                if l["kind"] == "text" {Text(l["text"].text).font(.caption2).lineLimit(1)}
                            };Spacer()
                            if l["locked"] == true {Image(systemName:"lock").font(.caption2)}
                        }.padding(8).background(l.id == selected ? Palette.board:Palette.side,in:RoundedRectangle(cornerRadius:7))
                    }.buttonStyle(.plain)
                }
            }.padding(17).frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    private func load() async {
        working = true; defer { working = false }
        do {
            let b = try await studio.bookDetail(bookID)
            let ids = b["pages"].items.map{$0["pageId"].text}
            if !ids.contains(pageID) { selectPage(ids.first ?? "") }
            for id in ids { guard !Task.isCancelled else{return}; _ = try await studio.page(id) }
        } catch { if !Task.isCancelled { message = error.localizedDescription } }
    }
    private func action(_ work:@escaping @MainActor () async throws -> Void) {
        Task { do { try await work() } catch { message = error.localizedDescription } }
    }
    private func selectPage(_ id:String){pageID = id; selected = nil}
    private func edit(_ replacement:JSONValue) {
        guard studio.canEdit,document != replacement else{return}
        history.append(EditStep(page:pageID,before:document,after:replacement))
        if history.count > 80 {history.removeFirst()}
        future = []; studio.edit(id:pageID,document:replacement)
    }
    private func updateLayers(_ new:[JSONValue]) { var d = document; d["layers"] = .array(new); edit(d) }
    private func add(_ kind:String,_ content:String) {
        guard layers.count < 200 else{return}
        let l = PageEditing.newLayer(kind:kind,document:document,content:content)
        updateLayers(layers + [l]); selected = l.id; spread = false; inspector = true
    }
    private func changeLayer(_ id:String,_ update:(inout JSONValue)->Void) {edit(PageEditing.changing(id,in:document,update:update))}
    private func scale(_ factor:Double) { if let selected { changeLayer(selected) { l in
        l["width"] = .number(max(1,min(10000,l["width"].double*factor)));l["height"] = .number(max(1,min(10000,l["height"].double*factor)))
    } } }
    private func rotate(_ delta:Double) { if let selected {changeLayer(selected){$0["rotation"] = .number(($0["rotation"].double+delta).truncatingRemainder(dividingBy:360))}} }
    private func duplicateLayer() { guard var l = layer else{return};l["id"] = .string(UUID().uuidString);l["x"] = .number(l["x"].double+30);l["y"] = .number(l["y"].double+30);updateLayers(layers + [l]);selected = l.id }
    private func deleteLayer() { updateLayers(layers.filter{$0.id != selected});selected = nil }
    private func reorderLayer(_ delta:Int) {
        guard let i = layers.firstIndex(where:{$0.id == selected}), layers.indices.contains(i+delta) else{return}
        var new = layers;new.swapAt(i,i+delta);updateLayers(new)
    }
    private func undo() { guard let step = history.popLast() else{return};future.append(step);selectPage(step.page);studio.edit(id:step.page,document:step.before) }
    private func redo() { guard let step = future.popLast() else{return};history.append(step);selectPage(step.page);studio.edit(id:step.page,document:step.after) }
    private func movePage(_ id:String,by:Int) {
        guard let i = pageIDs.firstIndex(of:id),pageIDs.indices.contains(i+by) else{return}
        var order = pageIDs;order.swapAt(i,i+by);setOrder(order,select:id)
    }
    private func setOrder(_ ids:[String],select:String?) {
        action {
            try await studio.flush()
            _ = try await studio.mutation("/books/\(bookID)/pages","PUT",["pageIds":.array(ids.map(JSONValue.string))])
            selectPage(select ?? ids.first ?? ""); history = []; future = []; await load()
        }
    }
    private func createPage(copy:String?) {
        action {
            try await studio.flush()
            let p:JSONValue
            if let copy {p = try await studio.mutation("/pages/\(copy)/duplicate","POST",[:])}
            else {p = try await studio.mutation("/pages","POST",["title":.string("Page \(pageIDs.count+1)"),"document":PageEditing.blank(width:book["pageWidth"],height:book["pageHeight"])])}
            var ids = pageIDs
            ids.insert(p.id,at:min(pageNumber,ids.count))
            _ = try await studio.mutation("/books/\(bookID)/pages","PUT",["pageIds":.array(ids.map(JSONValue.string))])
            selectPage(p.id);await load()
        }
    }
}

private func layerName(_ l:JSONValue)->String {
    switch l["kind"].text {case "washiTape":"Washi tape";case "": "Layer"; default:l["kind"].text.capitalized}
}
private func layerIcon(_ l:JSONValue)->String {
    switch l["kind"].text {case "text":"textformat";case "photo":"photo";case "washiTape":"bandage";case "map":"map";default:"star"}
}

private struct EditablePage: View {
    let document:JSONValue, client:ZakkaClient
    let selected:String?, editable:Bool
    let choose:(String?)->Void
    let move:(String,Double,Double)->Void
    @State private var translation = CGSize.zero
    var body: some View {
        let w = max(1,document["canvas"]["width"].double), h = max(1,document["canvas"]["height"].double)
        ZStack {
            PageArtwork(document:document,client:client).allowsHitTesting(false)
            GeometryReader { g in
                let factor = g.size.width/w
                ZStack(alignment:.topLeading) {
                    Color.clear.contentShape(Rectangle()).onTapGesture{choose(nil)}
                    ForEach(document["layers"].items,id:\.id) { l in
                        let active = selected == l.id
                        Rectangle().fill(Color.clear)
                            .overlay { if active { Rectangle().strokeBorder(.teal,lineWidth:2) } }
                            .contentShape(Rectangle())
                            .frame(width:max(1,l["width"].double*factor),height:max(1,l["height"].double*factor))
                            .rotationEffect(.degrees(l["rotation"].double))
                            .offset(x:l["x"].double*factor + (active ? translation.width:0),y:l["y"].double*factor + (active ? translation.height:0))
                            .accessibilityLabel("\(layerName(l)), \(l["text"].text)")
                            .onTapGesture{choose(l.id)}
                            .simultaneousGesture(DragGesture(minimumDistance:4,coordinateSpace:.named("page")).onChanged { d in
                                guard editable,l["locked"] != true else{return}
                                choose(l.id);translation = d.translation
                            }.onEnded{ d in
                                translation = .zero
                                guard editable,l["locked"] != true else{return}
                                move(l.id,d.translation.width/factor,d.translation.height/factor)
                            })
                    }
                }.frame(width:g.size.width,height:g.size.height,alignment:.topLeading).clipped().coordinateSpace(name:"page")
            }
        }.background(Color.white).aspectRatio(w/h,contentMode:.fit)
            .shadow(color:.black.opacity(0.14),radius:5,x:1,y:3)
    }
}

private struct TextEntry: View {
    @Environment(\.dismiss) var dismiss
    let title:String,initial:String,action:String
    let completion:(String)->Void
    @State private var text = ""
    var body: some View {
        NavigationStack {
            Form { Section("Content") {TextField("Text",text:$text,axis:.vertical).lineLimit(2...8).accessibilityIdentifier("layer.text")} }
                .navigationTitle(title).toolbar {
                    ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}
                    ToolbarItem(placement:.confirmationAction){Button(action){completion(text);dismiss()}.disabled(text.isEmpty || text.count > (title == "Page title" ? 120:2000))}
                }
        }.onAppear{text = initial}.presentationDetents([.medium])
    }
}

private struct AssetPicker: View {
    @Environment(Studio.self) var studio
    @Environment(\.dismiss) var dismiss
    let choose:(JSONValue)->Void
    @State private var search = ""
    var body: some View {
        NavigationStack {
            ScrollView {LazyVGrid(columns:[GridItem(.adaptive(minimum:120))]) {
                if let c = studio.client {ForEach((studio.snapshot?.photos ?? []).filter{search.isEmpty || $0["originalFilename"].text.localizedCaseInsensitiveContains(search)},id:\.id){ a in
                    Button {choose(a);dismiss()} label:{VStack(alignment:.leading){
                        AssetImage(asset:a,client:c).aspectRatio(1.4,contentMode:.fit)
                        Text(a["originalFilename"].text).font(.caption2).lineLimit(1)
                    }}.buttonStyle(.plain)
                }}
            }.padding() }
                .overlay { if studio.snapshot?.photos.isEmpty == true {ContentUnavailableView("No photos yet",systemImage:"photo",description:Text("Import photos from the Photos workspace first."))} }
                .searchable(text:$search).navigationTitle("Add a photo").toolbar{Button("Cancel"){dismiss()}}
        }
    }
}
