import AppKit

// Hammerspoon-style transient on-screen alerts.
enum Alert {
    private final class AlertWindow {
        let window: NSPanel
        var timer: Timer?

        init(message: String) {
            let label = NSTextField(labelWithString: message)
            label.font = .systemFont(ofSize: 20, weight: .medium)
            label.textColor = .white
            label.sizeToFit()

            let padding: CGFloat = 18
            let size = NSSize(width: label.frame.width + padding * 2,
                              height: label.frame.height + padding)

            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            bg.material = .hudWindow
            bg.state = .active
            bg.wantsLayer = true
            bg.layer?.cornerRadius = 12
            bg.layer?.masksToBounds = true
            bg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor

            label.frame.origin = NSPoint(x: padding, y: padding / 2)
            bg.addSubview(label)
            panel.contentView = bg

            if let screen = NSScreen.main {
                let sf = screen.visibleFrame
                panel.setFrameOrigin(NSPoint(x: sf.midX - size.width / 2,
                                             y: sf.minY + sf.height * 0.15))
            }
            window = panel
        }
    }

    private static var alerts: [Int: AlertWindow] = [:]
    private static var nextId = 0

    @discardableResult
    static func show(_ message: String, duration: Double = 2.0) -> Int {
        nextId += 1
        let id = nextId
        let alert = AlertWindow(message: message)
        alerts[id] = alert
        restack()
        alert.window.orderFrontRegardless()
        if duration < 900 {  // treat very large duration as "sticky"
            alert.timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
                close(id)
            }
        }
        return id
    }

    static func close(_ id: Int) {
        guard let alert = alerts.removeValue(forKey: id) else { return }
        alert.timer?.invalidate()
        alert.window.orderOut(nil)
        restack()
    }

    // Stack multiple alerts vertically so they don't overlap.
    private static func restack() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        var y = sf.minY + sf.height * 0.15
        for (_, alert) in alerts.sorted(by: { $0.key < $1.key }) {
            let w = alert.window
            w.setFrameOrigin(NSPoint(x: sf.midX - w.frame.width / 2, y: y))
            y += w.frame.height + 8
        }
    }
}
