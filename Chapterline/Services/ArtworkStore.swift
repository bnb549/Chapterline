import Foundation
import SwiftUI
import UIKit

enum ArtworkStore {
    static func coverURL(for book: Book) -> URL? {
        let directory = BookStorage.directory(for: book.id)
        if let override = book.artworkOverridePath {
            let url = directory.appendingPathComponent(override)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        let embedded = directory.appendingPathComponent(BookStorage.embeddedCoverName)
        if FileManager.default.fileExists(atPath: embedded.path) { return embedded }
        for name in BookStorage.folderCoverNames {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    static func image(for book: Book) -> UIImage {
        if let url = coverURL(for: book), let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            return image
        }
        return monogram(title: book.title, author: book.author)
    }

    static func data(for book: Book) -> Data? {
        if let url = coverURL(for: book) {
            return try? Data(contentsOf: url)
        }
        return monogram(title: book.title, author: book.author).jpegData(compressionQuality: 0.85)
    }

    static func writeEmbedded(_ data: Data, bookID: UUID) {
        let url = BookStorage.directory(for: bookID).appendingPathComponent(BookStorage.embeddedCoverName)
        let downsampled = downsample(data, maxDimension: 1024) ?? data
        try? downsampled.write(to: url, options: .atomic)
    }

    static func writeOverride(_ data: Data, book: Book) {
        let url = BookStorage.directory(for: book.id).appendingPathComponent(BookStorage.overrideCoverName)
        let downsampled = downsample(data, maxDimension: 1024) ?? data
        try? downsampled.write(to: url, options: .atomic)
        book.artworkOverridePath = BookStorage.overrideCoverName
    }

    static func copyFolderCover(from sourceDirectory: URL, bookID: UUID) {
        let destDir = BookStorage.directory(for: bookID)
        for name in BookStorage.folderCoverNames {
            let source = sourceDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: source.path) {
                let dest = destDir.appendingPathComponent(name)
                try? FileManager.default.copyItem(at: source, to: dest)
                return
            }
        }
    }

    static func monogram(title: String, author: String, size: CGFloat = 512) -> UIImage {
        let initials = initials(from: title)
        let colors = palette(from: title + author)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            colors.background.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            colors.accent.setFill()
            let band = CGRect(x: 0, y: size * 0.72, width: size, height: size * 0.28)
            context.fill(band)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size * 0.32, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let rect = CGRect(x: 0, y: size * 0.28, width: size, height: size * 0.4)
            (initials as NSString).draw(in: rect, withAttributes: attributes)
        }
    }

    static func averageColor(from image: UIImage) -> Color {
        guard let input = image.cgImage else { return Color(red: 0.12, green: 0.1, blue: 0.08) }
        let size = CGSize(width: 1, height: 1)
        let renderer = UIGraphicsImageRenderer(size: size)
        let pixel = renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .low
            ctx.cgContext.draw(input, in: CGRect(origin: .zero, size: size))
        }
        guard let data = pixel.cgImage?.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return Color(red: 0.12, green: 0.1, blue: 0.08)
        }
        return Color(
            red: Double(bytes[0]) / 255,
            green: Double(bytes[1]) / 255,
            blue: Double(bytes[2]) / 255
        )
    }

    private static func initials(from title: String) -> String {
        let words = title.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }
        if letters.isEmpty { return "CL" }
        return letters.joined()
    }

    private static func palette(from seed: String) -> (background: UIColor, accent: UIColor) {
        var hash: UInt64 = 5381
        for byte in seed.utf8 { hash = ((hash &<< 5) &+ hash) &+ UInt64(byte) }
        let hue = CGFloat(hash % 360) / 360
        let background = UIColor(hue: hue, saturation: 0.45, brightness: 0.28, alpha: 1)
        let accent = UIColor(hue: hue, saturation: 0.55, brightness: 0.55, alpha: 1)
        return (background, accent)
    }

    private static func downsample(_ data: Data, maxDimension: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image.jpegData(compressionQuality: 0.86) }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return scaled.jpegData(compressionQuality: 0.86)
    }
}
