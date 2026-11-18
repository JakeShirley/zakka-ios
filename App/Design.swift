import SwiftUI
import ZakkaCore

enum Palette {
    static let paper = Color(red: 0.969, green: 0.960, blue: 0.929)
    static let side = Color(red: 0.928, green: 0.925, blue: 0.880)
    static let board = Color(red: 0.875, green: 0.889, blue: 0.839)
    static let ink = Color(red: 0.111, green: 0.184, blue: 0.146)
    static let leaf = Color(red: 0.184, green: 0.350, blue: 0.259)
    static let muted = Color(red: 0.344, green: 0.382, blue: 0.333)
    static let line = ink.opacity(0.17)
    static let rust = Color(red: 0.571, green: 0.286, blue: 0.183)
}

struct Brand: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.3.layers.3d").font(.title2.weight(.medium))
                .frame(width: 40,height: 40).background(Palette.leaf, in: RoundedRectangle(cornerRadius: 11)).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 0) {
                Text("Zakka").font(.system(size: 30, weight: .medium, design: .serif))
                Eyebrow("Scrapbook studio", size: 9)
            }
        }.foregroundStyle(Palette.ink)
    }
}

struct Eyebrow: View {
    let text: String
    let size: CGFloat
    init(_ text: String, size: CGFloat = 10) { self.text = text; self.size = size }
    var body: some View { Text(text.uppercased()).font(.system(size: size, weight: .semibold, design: .monospaced)).tracking(1.35) }
}

struct StudioButton: ButtonStyle {
    var primary = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .padding(.horizontal, 17).padding(.vertical, 11)
            .foregroundStyle(primary ? Color.white : Palette.ink)
            .background(primary ? Palette.leaf : Palette.side, in: Capsule())
            .opacity(configuration.isPressed ? 0.68 : 1)
    }
}

struct PageHeading<Actions: View>: View {
    let section: String, title: String, subtitle: String
    @ViewBuilder let actions: Actions
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(section).foregroundStyle(Palette.rust)
            HStack(alignment: .center) {
                Text(title).font(.system(size: 48, weight: .regular, design: .serif)).minimumScaleFactor(0.65)
                Spacer(); actions
            }
            Text(subtitle).font(.subheadline).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

func bookSize(_ book: JSONValue) -> String {
    let w = book["pageWidth"].double / 300, h = book["pageHeight"].double / 300
    return "\(w.formatted(.number.precision(.fractionLength(0...1)))) × \(h.formatted(.number.precision(.fractionLength(0...1)))) in"
}

struct EmptyStudio: View {
    let icon: String, title: String, message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(Palette.leaf)
            Text(title).font(.title2).fontDesign(.serif)
            Text(message).font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
        }.padding(35).frame(maxWidth: .infinity)
    }
}
