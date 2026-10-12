import Foundation
import CoreGraphics

struct SpaceTile: Identifiable {
    let id: Int
    let rect: CGRect
}

enum SpaceMapLayout {
    static func tiles(weights: [(Int, Int64)], in bounds: CGRect) -> [SpaceTile] {
        let items = weights.filter { $0.1 > 0 }
        var result: [SpaceTile] = []
        func split(_ items: ArraySlice<(Int, Int64)>, _ rect: CGRect) {
            guard !items.isEmpty, rect.width > 0, rect.height > 0 else { return }
            if items.count == 1 { result.append(SpaceTile(id: items.first!.0, rect: rect)); return }
            let total = items.reduce(0.0) { $0 + Double($1.1) }
            var subtotal = 0.0
            var division = items.startIndex + 1
            for i in items.indices.dropLast() {
                subtotal += Double(items[i].1); division = i + 1
                if subtotal >= total / 2 { break }
            }
            let ratio = subtotal / total
            if rect.width >= rect.height {
                let width = rect.width * ratio
                split(items[..<division], CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height))
                split(items[division...], CGRect(x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height))
            } else {
                let height = rect.height * ratio
                split(items[..<division], CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height))
                split(items[division...], CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height))
            }
        }
        split(items[...], bounds)
        return result
    }
}
