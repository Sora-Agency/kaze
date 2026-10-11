import SwiftUI
import AppKit
import CoreText

enum SoraPalette {
    static func color(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static let main = color(light: 0xf3f2ed, dark: 0x181818)
    static let surface = color(light: 0xffffff, dark: 0x212226)
    static let elevated = color(light: 0xebeae4, dark: 0x292a2f)
    static let sidebar = color(light: 0xf7f6f1, dark: 0x1b1b1c)
    static let control = color(light: 0xffffff, dark: 0x1c1c1d)
    static let text = color(light: 0x11120f, dark: 0xf2f2f2)
    static let secondary = color(light: 0x666861, dark: 0xb7b7b7)
    static let muted = color(light: 0x92938c, dark: 0x8c8c8c)
    static let accent = color(light: 0x08afc0, dark: 0x00b2c4)
    static let accentHover = color(light: 0x0496a6, dark: 0x20c5d4)
    static let danger = color(light: 0xc84141, dark: 0xf17878)
    static let border = color(light: 0xd5d5ce, dark: 0x363638)
    static let borderSoft = color(light: 0xe2e1da, dark: 0x2d2e30)
    static let inputBorder = color(light: 0xd1d2cb, dark: 0x404247)
    static let onAccent = color(light: 0x07353b, dark: 0x072f35)
    static let switchThumb = color(light: 0xffffff, dark: 0xc8cad0)
}

enum SoraTypography {
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("DMSans-9ptRegular_Regular", size: size).weight(weight)
    }
    static func brand(_ size: CGFloat, weight: Font.Weight = .light) -> Font {
        .custom("RalewayRoman-Regular", size: size).weight(weight)
    }
}

@MainActor
enum SoraFonts {
    private static var registered = Set<String>()
    static func register(directory: URL? = nil) {
        guard let directory = directory ?? Bundle.main.resourceURL?.appendingPathComponent("Fonts") else { return }
        for file in ["DMSans.ttf", "Raleway.ttf"] {
            let url = directory.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: url.path), registered.insert(url.path).inserted else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

enum AppAppearance: String {
    case dark, light, system
    var title: String {
        switch self { case .dark: return L10n.text("Oscuro"); case .light: return L10n.text("Claro"); case .system: return L10n.text("Sistema") }
    }
    var scheme: ColorScheme? {
        switch self { case .dark: return .dark; case .light: return .light; case .system: return nil }
    }
}

struct SoraMark: View {
    var size: CGFloat = 38
    var resourceDirectory: URL? = nil
    var body: some View {
        if let directory = resourceDirectory ?? Bundle.main.resourceURL,
           let logo = NSImage(contentsOf: directory.appendingPathComponent("SoraLogo.png")) {
            Image(nsImage: logo).renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(SoraPalette.text)
                .frame(width: size, height: size * 222 / 290).accessibilityLabel("Sora")
        }
    }
}

struct SoraDivider: View {
    var body: some View { SoraPalette.borderSoft.frame(height: 1) }
}
