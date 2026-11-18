import SwiftUI
import ZakkaCore

struct SettingsView: View {
    @Environment(Studio.self) var studio
    @State private var system: JSONValue?
    @State private var confirm = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:26) {
                PageHeading(section:"Studio  /  04",title:"Settings",subtitle:"Your account and connected workspace.") { EmptyView() }
                if let user = studio.snapshot?.account {
                    section("Account",rows:[("Name",user["displayName"].text),("Email",user["primaryEmail"].text)])
                }
                section("Server",rows:[("Address",studio.address),("Status",studio.offline ? "Offline":"Connected"),("API version",studio.version),
                                       ("Runtime",system?["nodeVersion"].text ?? "—")])
                Button("Sign out",role:.destructive) { confirm = true }.buttonStyle(.bordered)
            }.padding(.horizontal,32).frame(maxWidth:900,alignment:.leading).frame(maxWidth:.infinity,alignment:.leading)
        }.task {
            guard !studio.offline, let c = studio.client else { return }
            do { system = try await c.json("/system/info") } catch { studio.handle(error) }
        }.alert("Sign out of this server?",isPresented:$confirm) {
            Button("Sign out",role:.destructive) { Task { do { if !studio.offline { try await studio.flush() }; try await studio.signOut() } catch { studio.handle(error) } } }
            Button("Cancel",role:.cancel) {}
        }
    }
    private func section(_ title:String,rows:[(String,String)]) -> some View {
        VStack(alignment:.leading,spacing:14) {
            Eyebrow(title).foregroundStyle(Palette.rust)
            ForEach(rows.indices,id:\.self) { i in
                Divider(); LabeledContent(rows[i].0,value:rows[i].1).font(.subheadline)
            }
        }.padding(20).background(Palette.side,in:RoundedRectangle(cornerRadius:12))
    }
}
