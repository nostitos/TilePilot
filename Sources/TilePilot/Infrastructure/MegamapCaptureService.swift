import AppKit
import CoreGraphics
import Foundation

final class MegamapCaptureService {
    struct ScreenDescriptor: Sendable {
        let displayID: CGDirectDisplayID
        let localizedName: String
        let frame: CGRect
        let visibleFrame: CGRect
    }

    func screenRecordingAuthorized() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    func requestScreenRecordingAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func capturesDirectoryURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appendingPathComponent("TilePilot", isDirectory: true)
            .appendingPathComponent("Megamap", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func removeCapture(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    func capture(display: DisplayState, desktopIndex: Int) throws -> MegamapCaptureRecord {
        let directory = try capturesDirectoryURL()
        guard let screen = resolveScreenDescriptor(for: display) else {
            throw NSError(
                domain: "MegamapCaptureService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not match display \(display.name) to a macOS screen."]
            )
        }
        let captureRect = captureRect(for: screen)
        let cgImage: CGImage?
        if let captureRect {
            cgImage = CGDisplayCreateImage(screen.displayID, rect: captureRect)
        } else {
            cgImage = CGDisplayCreateImage(screen.displayID)
        }
        guard let cgImage else {
            throw NSError(
                domain: "MegamapCaptureService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Screen capture returned no image for \(display.name)."]
            )
        }

        let imageRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = imageRep.representation(using: .png, properties: [:]) else {
            throw NSError(
                domain: "MegamapCaptureService",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode screenshot for \(display.name)."]
            )
        }

        let timestamp = Date()
        let fileName = "display-\(display.id)-desktop-\(desktopIndex)-\(Int(timestamp.timeIntervalSince1970)).png"
        let fileURL = directory.appendingPathComponent(fileName)
        try pngData.write(to: fileURL, options: .atomic)

        return MegamapCaptureRecord(
            displayID: display.id,
            displayName: display.name,
            displayAspectRatio: captureAspectRatio(for: screen, fallbackDisplay: display),
            desktopIndex: desktopIndex,
            capturedFrameX: captureFrame(for: screen, fallbackDisplay: display).origin.x,
            capturedFrameY: captureFrame(for: screen, fallbackDisplay: display).origin.y,
            capturedFrameW: captureFrame(for: screen, fallbackDisplay: display).size.width,
            capturedFrameH: captureFrame(for: screen, fallbackDisplay: display).size.height,
            screenshotPath: fileURL.path,
            capturedAt: timestamp
        )
    }

    func capture(display: DisplayState, desktopIndex: Int, screen: ScreenDescriptor) throws -> MegamapCaptureRecord {
        let directory = try capturesDirectoryURL()
        let captureRect = captureRect(for: screen)
        let cgImage: CGImage?
        if let captureRect {
            cgImage = CGDisplayCreateImage(screen.displayID, rect: captureRect)
        } else {
            cgImage = CGDisplayCreateImage(screen.displayID)
        }
        guard let cgImage else {
            throw NSError(
                domain: "MegamapCaptureService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Screen capture returned no image for \(display.name)."]
            )
        }

        let imageRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = imageRep.representation(using: .png, properties: [:]) else {
            throw NSError(
                domain: "MegamapCaptureService",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode screenshot for \(display.name)."]
            )
        }

        let timestamp = Date()
        let fileName = "display-\(display.id)-desktop-\(desktopIndex)-\(Int(timestamp.timeIntervalSince1970)).png"
        let fileURL = directory.appendingPathComponent(fileName)
        try pngData.write(to: fileURL, options: .atomic)

        return MegamapCaptureRecord(
            displayID: display.id,
            displayName: display.name,
            displayAspectRatio: captureAspectRatio(for: screen, fallbackDisplay: display),
            desktopIndex: desktopIndex,
            capturedFrameX: captureFrame(for: screen, fallbackDisplay: display).origin.x,
            capturedFrameY: captureFrame(for: screen, fallbackDisplay: display).origin.y,
            capturedFrameW: captureFrame(for: screen, fallbackDisplay: display).size.width,
            capturedFrameH: captureFrame(for: screen, fallbackDisplay: display).size.height,
            screenshotPath: fileURL.path,
            capturedAt: timestamp
        )
    }

    func resolveScreenDescriptors(for displays: [DisplayState]) -> [Int: ScreenDescriptor] {
        let availableScreens = currentScreenDescriptors()
        guard !availableScreens.isEmpty else { return [:] }
        var resolved: [Int: ScreenDescriptor] = [:]
        for display in displays {
            if let descriptor = bestScreenDescriptor(for: display, from: availableScreens) {
                resolved[display.id] = descriptor
            }
        }
        return resolved
    }

    private func resolveScreenDescriptor(for display: DisplayState) -> ScreenDescriptor? {
        bestScreenDescriptor(for: display, from: currentScreenDescriptors())
    }

    private func currentScreenDescriptors() -> [ScreenDescriptor] {
        NSScreen.screens.compactMap { screen -> ScreenDescriptor? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return ScreenDescriptor(
                displayID: CGDirectDisplayID(number.uint32Value),
                localizedName: {
                    if #available(macOS 10.15, *) {
                        return screen.localizedName
                    }
                    return "Display"
                }(),
                frame: screen.frame,
                visibleFrame: screen.visibleFrame
            )
        }
    }

    private func captureRect(for screen: ScreenDescriptor) -> CGRect? {
        nil
    }

    private func captureAspectRatio(for screen: ScreenDescriptor, fallbackDisplay: DisplayState) -> Double {
        let frame = captureFrame(for: screen, fallbackDisplay: fallbackDisplay)
        return max(frame.width, 1) / max(frame.height, 1)
    }

    private func captureFrame(for screen: ScreenDescriptor, fallbackDisplay: DisplayState) -> CGRect {
        return CGRect(
            x: fallbackDisplay.frameX,
            y: fallbackDisplay.frameY,
            width: fallbackDisplay.frameW,
            height: fallbackDisplay.frameH
        )
    }

    private func bestScreenDescriptor(for display: DisplayState, from descriptors: [ScreenDescriptor]) -> ScreenDescriptor? {
        let targetFrame = CGRect(x: display.frameX, y: display.frameY, width: display.frameW, height: display.frameH)
        var best: ScreenDescriptor?
        var bestScore: CGFloat = -.greatestFiniteMagnitude

        for descriptor in descriptors {
            let intersection = descriptor.frame.intersection(targetFrame)
            let overlapArea = intersection.isNull ? 0 : (intersection.width * intersection.height)
            let exactNameBonus: CGFloat = descriptor.localizedName == display.name ? 1_000_000 : 0
            let exactFrameBonus: CGFloat = descriptor.frame.equalTo(targetFrame) ? 2_000_000 : 0
            let score = overlapArea + exactNameBonus + exactFrameBonus
            if score > bestScore {
                bestScore = score
                best = descriptor
            }
        }

        return best
    }
}
