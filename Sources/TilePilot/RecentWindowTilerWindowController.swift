import AppKit
import Combine
import SwiftUI

@MainActor
final class RecentWindowTilerWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel
    private var cancellable: AnyCancellable?
    private var isClosingFromModel = false

    init(model: AppModel) {
        self.model = model

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Pick Windows to Tile"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace]
        panel.contentViewController = NSHostingController(rootView: RecentWindowTilerPickerView(model: model))

        super.init(window: panel)
        panel.delegate = self

        cancellable = model.$recentWindowTilerState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.syncPresentation(state)
            }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        guard !isClosingFromModel else { return }
        model.dismissRecentWindowTiler()
    }

    private func syncPresentation(_ state: RecentWindowTilerPresentationState?) {
        guard let window else { return }
        guard let state else {
            if window.isVisible {
                isClosingFromModel = true
                window.close()
                isClosingFromModel = false
            }
            return
        }

        let shouldCenter = !window.isVisible
        resizeWindow(for: state)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        if shouldCenter {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func resizeWindow(for state: RecentWindowTilerPresentationState) {
        guard let window else { return }
        let visibleRows = min(max(state.candidates.count, 1), 8)
        let rowHeight: CGFloat = 52
        let rowSpacing: CGFloat = 6
        let listHeight = CGFloat(visibleRows) * rowHeight + CGFloat(max(0, visibleRows - 1)) * rowSpacing
        let contentHeight = 158 + listHeight
        window.setContentSize(NSSize(width: 500, height: contentHeight))
    }
}
