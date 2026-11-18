import SwiftUI
import ZakkaCore

struct ExportView: View {
    @Environment(Studio.self) var studio
    @Environment(\.dismiss) var dismiss
    let book:JSONValue,page:JSONValue
    @State private var single = false
    @State private var format = "pdf"
    @State private var preset = "digital"
    @State private var dpi = 150
    @State private var busy = false
    @State private var url:URL?
    @State private var error = ""
    @State private var job:Task<Void,Never>?
    var body: some View {
        NavigationStack {
            Form {
                Section("Export settings") {
                    Picker("Content",selection:$single) {Text("Entire book").tag(false);Text("Current page").tag(true)}
                    Picker("Format",selection:$format) {Text("PDF").tag("pdf");Text(single ? "PNG":"Page PNGs (ZIP)").tag("png")}
                    Picker("Preset",selection:$preset) {Text("Digital").tag("digital");Text("Print").tag("print")}
                    Stepper("Resolution: \(dpi) DPI",value:$dpi,in:72...600,step:1)
                }.disabled(busy)
                if busy {ProgressView("Rendering on your server…")}
                else {
                    Button("Create export",systemImage:"arrow.down.doc"){job = Task {await render()}}
                    if let url { ShareLink(item:url) { Label("Share exported file",systemImage:"square.and.arrow.up") } }
                    if !error.isEmpty {Text(error).foregroundStyle(.red)}
                }
            }.navigationTitle("Export").toolbar{ Button("Done"){dismiss()} }
        }.onChange(of:single){_,_ in url = nil}.onChange(of:format){_,_ in url = nil}
            .onChange(of:dpi){_,_ in url = nil}.onChange(of:preset){_,v in url = nil;dpi = v == "print" ? 300:150}
            .onDisappear { job?.cancel() }
    }
    private func render() async {
        guard let client = studio.client else{return}
        busy = true;error = "";url = nil;defer{busy = false}
        do {
            try await studio.flush()
            var request:JSONValue = ["format":.string(format),"preset":.string(preset),"dpi":.number(Double(dpi))]
            request[single ? "pageId":"bookId"] = .string(single ? page.id:book.id)
            var job = try await studio.mutation("/exports","POST",request)
            let clock = ContinuousClock(), deadline = clock.now.advanced(by:.seconds(300))
            while ["running","queued"].contains(job["status"].text) {
                guard clock.now < deadline else {throw URLError(.timedOut)}
                try await Task.sleep(for:.milliseconds(500))
                job = try await client.json("/exports/\(job.id)")
            }
            guard job["status"] == "completed" else{throw ClientError.http(422,job["errorMessage"].text.isEmpty ? "Export did not complete." : job["errorMessage"].text)}
            let bytes = try await client.data("/exports/\(job.id)/content")
            let ext = format == "png" && !single ? "zip":format
            let title = (single ? page.title:book.title).components(separatedBy:CharacterSet.alphanumerics.union(.whitespaces).inverted).joined(separator:" ").trimmingCharacters(in:.whitespaces)
            let folder = URL.temporaryDirectory.appending(path:UUID().uuidString,directoryHint:.isDirectory)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let path = folder.appending(path:title.isEmpty ? "Zakka export":title).appendingPathExtension(ext)
            try bytes.write(to:path);url = path
        } catch {if !Task.isCancelled {self.error = error.localizedDescription}}
    }
}
