import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    let alwaysOnTop: Bool

    func makeNSView(context: Context) -> ConfiguratorView {
        let view = ConfiguratorView()
        view.alwaysOnTop = alwaysOnTop
        return view
    }

    func updateNSView(_ nsView: ConfiguratorView, context: Context) {
        nsView.alwaysOnTop = alwaysOnTop
        nsView.configureWindow()
    }
}

final class ConfiguratorView: NSView {
    var alwaysOnTop = false
    private var hasPresentedWindow = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.borderless, .fullSizeContentView]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.level = alwaysOnTop ? .floating : .normal
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 164, height: 164)
        window.maxSize = NSSize(width: 164, height: 164)

        if !hasPresentedWindow {
            hasPresentedWindow = true
            window.center()
            window.orderFrontRegardless()
        }
    }
}
