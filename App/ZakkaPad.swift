import SwiftUI
import ZakkaCore

@main struct ZakkaPadApp: App {
    @State private var studio = Studio()
    var body: some Scene {
        WindowGroup {
            Group {
                if studio.restoring { ProgressView("Opening studio…") }
                else if studio.isSignedIn { WorkspaceView() }
                else { SignInView() }
            }
            .environment(studio).tint(Palette.leaf).preferredColorScheme(.light)
            .task { if studio.restoring { await studio.restore() } }
            .alert("Zakka", isPresented: Binding(get: { studio.error != nil }, set: { if !$0 { studio.error = nil } })) {
                Button("OK") { studio.error = nil }
            } message: { Text(studio.error ?? "") }
        }
    }
}

private enum SectionChoice: String, CaseIterable {
    case books = "Books", photos = "Photos", grid = "Image grid", settings = "Settings"
    var symbol: String { switch self { case .books: "books.vertical"; case .photos: "photo.on.rectangle.angled"; case .grid: "square.grid.3x3"; case .settings: "gearshape" } }
}

private struct WorkspaceView: View {
    @Environment(Studio.self) var studio
    @State private var tab = SectionChoice.books
    @State private var visibility = NavigationSplitViewVisibility.all
    @State private var preferredColumn: NavigationSplitViewColumn = .detail
    var body: some View {
        @Bindable var studio = studio
        NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $preferredColumn) {
            VStack(alignment: .leading, spacing: 8) {
                Brand().padding(.bottom, 40)
                Eyebrow("Workspace").foregroundStyle(Palette.muted).padding(.bottom, 6)
                ForEach(SectionChoice.allCases, id: \.self) { item in
                    Button {
                        tab = item; preferredColumn = .detail
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol).frame(width: 22)
                            Text(item.rawValue)
                            Spacer()
                            if item == .books || item == .photos {
                                Text("\((item == .books ? studio.snapshot?.books.count : studio.snapshot?.photos.count) ?? 0)")
                                    .font(.caption.monospacedDigit()).opacity(0.7)
                            }
                        }.font(.subheadline.weight(.semibold)).padding(.horizontal,12).frame(height: 44)
                            .background(tab == item ? Palette.leaf : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(tab == item ? .white : Palette.ink)
                    }.buttonStyle(.plain).accessibilityIdentifier("nav.\(item.rawValue)")
                }
                Spacer()
                Divider()
                HStack(spacing: 9) {
                    Image(systemName: "server.rack")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(studio.offline ? "Offline workspace" : "Connected server").font(.caption.weight(.semibold))
                        Text(studio.client?.baseURL.host ?? "").font(.caption2.monospaced()).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Circle().fill(studio.offline ? Palette.rust : Palette.leaf).frame(width: 8, height: 8)
                }.padding(.top, 8)
            }.padding(.horizontal, 20).padding(.vertical, 24)
                .background(Palette.side.ignoresSafeArea()).toolbarBackground(.hidden, for: .navigationBar)
                .navigationSplitViewColumnWidth(min: 205, ideal: 220, max: 255)
        } detail: {
            VStack(spacing: 0) {
                if studio.offline {
                    HStack { Label("Offline · cached workspace is read-only", systemImage: "wifi.slash"); Spacer(); Button("Reconnect") { Task { await studio.refresh() } } }
                        .font(.caption).padding(10).background(Palette.board)
                }
                switch tab { case .books: BooksView(); case .photos: PhotosView(); case .grid: GridView(); case .settings: SettingsView() }
            }.foregroundStyle(Palette.ink).background(Palette.paper.ignoresSafeArea())
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar { ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await studio.refresh() } } label: { Label("Refresh workspace", systemImage: "arrow.clockwise") }
                        .disabled(studio.refreshing)
                } }
        }
        .navigationSplitViewStyle(.balanced)
        .fullScreenCover(isPresented: Binding(get: { studio.activeBook != nil }, set: { if !$0 { studio.activeBook = nil } })) {
            if let id = studio.activeBook { EditorView(bookID: id).id(id).environment(studio).interactiveDismissDisabled() }
        }
    }
}

struct SignInView: View {
    @Environment(Studio.self) var studio
    @State private var server = ""
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var register = false
    @State private var busy = false
    @State private var message = ""

    var body: some View {
        ZStack {
            Palette.side.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    Brand().padding(.bottom, 14)
                    Eyebrow("01  /  Workspace access").foregroundStyle(Palette.rust)
                    Text(register ? "Start a studio." : "Open your studio.").font(.system(size: 42, design: .serif))
                    Text("Connect to your Zakka server to work with your books and photos.").foregroundStyle(Palette.muted)
                    Group {
                        TextField("Server URL", text: $server).keyboardType(.URL).textContentType(.URL).accessibilityIdentifier("server")
                        if !studio.profiles.isEmpty {
                            Menu("Saved servers") { ForEach(studio.profiles, id: \.self) { value in Button(value) { server = value } } }
                        }
                        if register { TextField("Display name", text: $name).textContentType(.name) }
                        TextField("Email", text: $email).keyboardType(.emailAddress).textContentType(.username).accessibilityIdentifier("email")
                        SecureField(register ? "Password (12+ characters)" : "Password", text: $password)
                            .textContentType(register ? .newPassword : .password).accessibilityIdentifier("password")
                    }.textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(.red).accessibilityLabel("Error: \(message)") }
                    Button { submit() } label: {
                        HStack { if busy { ProgressView().tint(.white) }; Text(register ? "Create account" : "Sign in"); Image(systemName: "arrow.right") }
                    }.buttonStyle(StudioButton()).disabled(busy || email.isEmpty || password.isEmpty || server.isEmpty || (register && name.isEmpty))
                    Button(register ? "Already have an account? Sign in" : "Create an account on this server") { register.toggle(); message = "" }.font(.footnote)
                }.padding(40).frame(maxWidth: 450).background(Palette.paper, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.line)).padding(36).frame(maxWidth:.infinity)
            }.scrollBounceBehavior(.basedOnSize)
        }.foregroundStyle(Palette.ink).onAppear { server = studio.address }
    }
    private func submit() {
        busy = true; message = ""
        Task {
            defer { busy = false }
            do { try await studio.connect(address: server, email: email, password: password, name: name, register: register) }
            catch { message = error.localizedDescription }
        }
    }
}
