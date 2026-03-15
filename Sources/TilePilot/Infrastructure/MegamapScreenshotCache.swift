import AppKit
import Foundation
import ImageIO

@MainActor
final class MegamapScreenshotCache {
    static let shared = MegamapScreenshotCache()

    private let cache = NSCache<NSString, NSImage>()
    private var keysByPath: [String: [NSString]] = [:]

    func image(for path: String, idealSize: CGSize) -> NSImage? {
        let maxDimension = max(idealSize.width, idealSize.height)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let targetPixelSize = max(512, Int((maxDimension * scale).rounded(.up)))
        let cacheKey = "\(path)|\(targetPixelSize)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let url = URL(fileURLWithPath: path)
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: targetPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldCache: true,
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: cacheKey)
        keysByPath[path, default: []].append(cacheKey)
        return image
    }

    func removeImage(at path: String) {
        guard let keys = keysByPath.removeValue(forKey: path) else { return }
        for key in keys {
            cache.removeObject(forKey: key)
        }
    }

    func clear() {
        cache.removeAllObjects()
        keysByPath.removeAll()
    }
}
