import AppKit
import Foundation
import ImageIO

final class MegamapTransientCaptureStore: @unchecked Sendable {
    static let shared = MegamapTransientCaptureStore()

    private let lock = NSLock()
    private var imagesByKey: [String: CGImage] = [:]

    private init() {}

    func store(_ image: CGImage, for key: String) {
        lock.lock()
        imagesByKey[key] = image
        lock.unlock()
    }

    func image(for key: String) -> CGImage? {
        lock.lock()
        let image = imagesByKey[key]
        lock.unlock()
        return image
    }

    func contains(_ key: String) -> Bool {
        lock.lock()
        let exists = imagesByKey[key] != nil
        lock.unlock()
        return exists
    }

    func removeImage(for key: String) {
        lock.lock()
        imagesByKey.removeValue(forKey: key)
        lock.unlock()
    }
}

@MainActor
final class MegamapScreenshotCache {
    static let shared = MegamapScreenshotCache()

    private let cache = NSCache<NSString, NSImage>()
    private var keysByPath: [String: Set<String>] = [:]

    private init() {
        cache.countLimit = 24
        cache.totalCostLimit = 128 * 1024 * 1024
    }

    func image(for path: String, idealSize: CGSize) -> NSImage? {
        if let transientImage = MegamapTransientCaptureStore.shared.image(for: path) {
            return image(forTransientCapture: transientImage, cacheKeyPath: path, idealSize: idealSize)
        }

        let maxDimension = max(idealSize.width, idealSize.height)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let targetPixelSize = max(512, Int((maxDimension * scale).rounded(.up)))
        let cacheKeyString = "\(path)|\(targetPixelSize)"
        let cacheKey = cacheKeyString as NSString
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
        let cost = max(1, cgImage.bytesPerRow * cgImage.height)
        cache.setObject(image, forKey: cacheKey, cost: cost)
        keysByPath[path, default: []].insert(cacheKeyString)
        return image
    }

    private func image(forTransientCapture cgImage: CGImage, cacheKeyPath: String, idealSize: CGSize) -> NSImage {
        let maxDimension = max(idealSize.width, idealSize.height)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let targetPixelSize = max(512, Int((maxDimension * scale).rounded(.up)))
        let cacheKeyString = "\(cacheKeyPath)|\(targetPixelSize)"
        let cacheKey = cacheKeyString as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let cost = max(1, cgImage.bytesPerRow * cgImage.height)
        cache.setObject(image, forKey: cacheKey, cost: cost)
        keysByPath[cacheKeyPath, default: []].insert(cacheKeyString)
        return image
    }

    func removeImage(at path: String) {
        guard let keys = keysByPath.removeValue(forKey: path) else { return }
        for key in keys {
            cache.removeObject(forKey: key as NSString)
        }
    }

    func clear() {
        cache.removeAllObjects()
        keysByPath.removeAll()
    }
}
