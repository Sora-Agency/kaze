import AppKit
import Foundation

final class LogoReader: NSObject, XMLParserDelegate {
    var paths: [String] = []
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if element == "path", let data = attributes["d"] { paths.append(data) }
    }
}
guard CommandLine.arguments.count == 3 else {
    fatalError("Uso: GenerateIcon.swift logo.svg directorio-de-salida")
}
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let output = CommandLine.arguments[2]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
let reader = LogoReader()
let xml = XMLParser(data: try Data(contentsOf: source))
xml.delegate = reader
guard xml.parse(), !reader.paths.isEmpty else { fatalError("No se pudo leer el logo original de Sora") }
let expression = try NSRegularExpression(pattern: #"[A-Za-z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?"#)
let logo = CGMutablePath()
for data in reader.paths {
    let tokens = expression.matches(in: data, range: NSRange(data.startIndex..., in: data)).map { String(data[Range($0.range, in: data)!]) }
    var index = 0
    var command = ""
    var current = CGPoint.zero
    func number() -> CGFloat {
        guard index < tokens.count, let value = Double(tokens[index]) else { fatalError("Coordenada SVG no válida") }
        index += 1
        return CGFloat(value)
    }
    func point() -> CGPoint { let x = number(); return CGPoint(x: x, y: number()) }
    while index < tokens.count {
        if tokens[index].first!.isLetter { command = tokens[index]; index += 1 }
        switch command {
        case "M": current = point(); logo.move(to: current); command = "L"
        case "L": current = point(); logo.addLine(to: current)
        case "H": current.x = number(); logo.addLine(to: current)
        case "V": current.y = number(); logo.addLine(to: current)
        case "C": let a = point(); let b = point(); current = point(); logo.addCurve(to: current, control1: a, control2: b)
        case "Z": logo.closeSubpath(); command = ""
        default: fatalError("Comando SVG no compatible: \(command)")
        }
    }
}
func drawLogo(in rect: CGRect) {
    let context = NSGraphicsContext.current!.cgContext
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: rect.width / 290, y: -rect.height / 222)
    context.addPath(logo)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    context.restoreGState()
}
func png(width: Int, height: Int, path: String, draw: (CGRect) -> Void) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    draw(CGRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
try png(width: 1160, height: 888, path: output + "/SoraLogo.png") { drawLogo(in: $0) }
try FileManager.default.createDirectory(atPath: output + "/AppIcon.iconset", withIntermediateDirectories: true)
func icon(_ pixels: Int, path: String) throws {
    try png(width: pixels, height: pixels, path: path) { _ in
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let background = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 210, yRadius: 210)
        NSColor(srgbRed: 0.094, green: 0.094, blue: 0.094, alpha: 1).setFill()
        background.fill()
        NSColor.white.withAlphaComponent(0.1).setStroke()
        background.lineWidth = 2; background.stroke()
        drawLogo(in: CGRect(x: 162, y: 244, width: 700, height: 700 * 222 / 290))
    }
}
for base in [16, 32, 128, 256, 512] {
    try icon(base, path: output + "/AppIcon.iconset/icon_\(base)x\(base).png")
    try icon(base * 2, path: output + "/AppIcon.iconset/icon_\(base)x\(base)@2x.png")
}
