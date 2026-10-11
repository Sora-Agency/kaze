import AppKit
import Foundation

@main
struct DMGLayoutTests {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Expected the mounted volume and background alias") }
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let background = folder.appendingPathComponent(".background/install.tiff")
        let alias = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        guard let bookmark = CFURLCreateBookmarkDataFromAliasRecord(nil, alias as CFData)?.takeRetainedValue() else {
            fatalError("Cannot decode the portable background alias")
        }
        var stale = false
        let target = try URL(resolvingBookmarkData: bookmark as Data, options: [.withoutUI, .withoutMounting],
                             relativeTo: nil, bookmarkDataIsStale: &stale)
        guard target.resolvingSymlinksInPath() == background.resolvingSymlinksInPath() else {
            fatalError("Background alias does not resolve inside the converted image")
        }
        guard let image = NSImage(contentsOf: background), image.size == NSSize(width: 640, height: 400) else {
            fatalError("Background must match the Finder content area")
        }
        let sizes = image.representations.map { "\($0.pixelsWide)x\($0.pixelsHigh)" }
        guard Set(sizes) == ["640x400", "1280x800"] else { fatalError("Background needs standard and Retina representations") }
        print("PASS: Portable background alias resolves without mounting a build image; standard and Retina sizes verified")
    }
}
