import AppKit
import CoreText
import Foundation

extension Data {
    mutating func appendWord(_ value: UInt32) {
        var value = value.bigEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}

func mountPoint(_ url: URL) throws -> String {
    let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as! [String: Any]
    let entities = plist["system-entities"] as! [[String: Any]]
    guard let path = entities.compactMap({ $0["mount-point"] as? String }).first else {
        throw CocoaError(.fileNoSuchFile)
    }
    return path
}

func backgroundAlias(image: URL, folder: URL) throws -> Data {
    guard let data = KazeCreateBackgroundAlias(folder.path, image.path) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data as Data
}

func writeLayout(to folder: URL, alias: Data) throws {
    var records: [Data] = []
    func record(_ name: String, _ code: String, _ type: String, _ value: Data) {
        var data = Data()
        data.appendWord(UInt32(name.utf16.count))
        data.append(name.data(using: .utf16BigEndian)!)
        data.append(contentsOf: (code + type).utf8)
        if type == "blob" { data.appendWord(UInt32(value.count)) }
        data.append(value)
        records.append(data)
    }
    func plist(_ code: String, _ value: [String: Any]) throws {
        record(".", code, "blob", try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0))
    }
    try plist("bwsp", [
        "WindowBounds": "{{180, 120}, {640, 432}}", "ShowToolbar": false,
        "ShowSidebar": false, "ShowStatusBar": false, "ShowTabView": false,
        "ShowPathbar": false, "ContainerShowSidebar": false
    ])
    record(".", "icvl", "type", Data("icnv".utf8))
    try plist("icvp", [
        "viewOptionsVersion": 1, "backgroundType": 2, "backgroundImageAlias": alias,
        "backgroundColorRed": 1.0, "backgroundColorGreen": 1.0, "backgroundColorBlue": 1.0,
        "iconSize": 88.0, "textSize": 14.0, "gridSpacing": 100.0,
        "gridOffsetX": 0.0, "gridOffsetY": 0.0, "arrangeBy": "none",
        "labelOnBottom": true, "showItemInfo": false, "showIconPreview": false,
        "scrollPositionX": 0.0, "scrollPositionY": 0.0
    ])
    var version = Data(); version.appendWord(1)
    record(".", "vSrn", "long", version)
    record(".", "vstl", "type", Data("icnv".utf8))
    for (name, x) in [("Applications", UInt32(468)), ("Kaze.app", UInt32(172))] {
        var position = Data()
        for word in [x, 244, UInt32.max, 0xffff0000] { position.appendWord(word) }
        record(name, "Iloc", "blob", position)
    }
    var tree = Data()
    tree.appendWord(0); tree.appendWord(UInt32(records.count))
    records.forEach { tree.append($0) }
    guard tree.count <= 4096 else { throw CocoaError(.fileWriteOutOfSpace) }
    var data = Data(count: 8196)
    func store(_ block: Data, at offset: Int) {
        data.replaceSubrange(offset..<(offset + block.count), with: block)
    }
    var header = Data()
    header.appendWord(1); header.append(contentsOf: "Bud1".utf8)
    for word: UInt32 in [2048, 2048, 2048] { header.appendWord(word) }
    store(header, at: 0)
    var treeHeader = Data()
    for word: UInt32 in [2, 0, UInt32(records.count), 1, 4096] { treeHeader.appendWord(word) }
    store(treeHeader, at: 36)
    var allocator = Data()
    allocator.appendWord(3); allocator.appendWord(0)
    for word: UInt32 in [2048 | 11, 32 | 5, 4096 | 12] { allocator.appendWord(word) }
    allocator.append(Data(count: 253 * 4))
    allocator.appendWord(1); allocator.append(4); allocator.append(contentsOf: "DSDB".utf8); allocator.appendWord(1)
    for bit in 0..<32 {
        let free = (6...10).contains(bit) || (13...30).contains(bit)
        allocator.appendWord(free ? 1 : 0)
        if free { allocator.appendWord(UInt32(1) << bit) }
    }
    store(allocator, at: 2052)
    store(tree, at: 4100)
    try data.write(to: folder.appendingPathComponent(".DS_Store"))
}

func drawBackground(folder: URL) throws -> URL {
    let resources = folder.appendingPathComponent("Kaze.app/Contents/Resources")
    for font in ["DMSans", "Raleway"] {
        CTFontManagerRegisterFontsForURL(resources.appendingPathComponent("Fonts/\(font).ttf") as CFURL, .process, nil)
    }
    let width: CGFloat = 640
    let height: CGFloat = 400
    func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    let graphite = color(0x11120f)
    let secondary = color(0x666861)
    let accent = color(0x08afc0)
    func rect(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
        NSRect(x: x, y: 400 - top - height, width: width, height: height)
    }
    func text(_ value: String, x: CGFloat = 40, top: CGFloat, width: CGFloat = 560,
              size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular,
              alignment: NSTextAlignment = .center, brand: Bool = false) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let name = brand ? "RalewayRoman-Regular" : "DMSans-9ptRegular_Regular"
        let descriptor = NSFontDescriptor(name: name, size: size)
            .addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]])
        let font = NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
        (value as NSString).draw(in: rect(x: x, top: top, width: width, height: size + 9), withAttributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph
        ])
    }
    var representations: [NSBitmapImageRep] = []
    for scale in [1, 2] {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        color(0xf3f2ed).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        if let logo = NSImage(contentsOf: resources.appendingPathComponent("SoraLogo.png")),
           let mask = logo.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let context = NSGraphicsContext.current!.cgContext
            context.saveGState()
            context.clip(to: rect(x: 42, top: 35, width: 46, height: 46 * 222 / 290), mask: mask)
            graphite.setFill()
            rect(x: 42, top: 35, width: 46, height: 46 * 222 / 290).fill()
            context.restoreGState()
        }
        text("Kaze", x: 102, top: 24, width: 210, size: 32, color: graphite, alignment: .left, brand: true)
        text("by Sora Agency", x: 103, top: 65, width: 210, size: 11, color: secondary, alignment: .left)
        let badge = NSBezierPath(roundedRect: rect(x: 520, top: 39, width: 78, height: 28), xRadius: 14, yRadius: 14)
        color(0xe6e6df).setFill(); badge.fill()
        text("macOS", x: 520, top: 45, width: 78, size: 11, color: secondary, weight: .medium)
        color(0xdedfd8).setFill()
        rect(x: 40, top: 94, width: 560, height: 1).fill()
        text("Arrastra Kaze a Aplicaciones", top: 117, size: 20, color: graphite, weight: .semibold)
        text("Drag Kaze to Applications", top: 149, size: 13, color: secondary)
        for x: CGFloat in [102, 398] {
            let panel = NSBezierPath(roundedRect: rect(x: x, top: 187, width: 140, height: 146), xRadius: 20, yRadius: 20)
            NSColor.white.setFill(); panel.fill()
            color(0xe2e1da).setStroke(); panel.lineWidth = 1; panel.stroke()
        }
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 298, y: height - 244)); arrow.line(to: NSPoint(x: 342, y: height - 244))
        arrow.move(to: NSPoint(x: 320, y: height - 222)); arrow.line(to: NSPoint(x: 342, y: height - 244))
        arrow.line(to: NSPoint(x: 320, y: height - 266))
        arrow.lineWidth = 2.5; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
        accent.setStroke(); arrow.stroke()
        text("Abre Kaze desde Aplicaciones · Open Kaze from Applications", top: 363, size: 11, color: secondary)
        NSGraphicsContext.restoreGraphicsState()
        representations.append(bitmap)
    }
    let image = folder.appendingPathComponent(".background/install.tiff")
    try FileManager.default.createDirectory(at: image.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let data = NSBitmapImageRep.representationOfImageReps(in: representations, using: .tiff,
        properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw.rawValue]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: image)
    return image
}

guard CommandLine.arguments.count == 3 else {
    fatalError("Uso: GenerateDMG.swift mount-point plist | layout volumen")
}
let url = URL(fileURLWithPath: CommandLine.arguments[2])
if CommandLine.arguments[1] == "mount-point" {
    print(try mountPoint(url))
} else if CommandLine.arguments[1] == "layout" {
    let image = try drawBackground(folder: url)
    try writeLayout(to: url, alias: backgroundAlias(image: image, folder: url))
} else {
    fatalError("Acción de distribución desconocida")
}
