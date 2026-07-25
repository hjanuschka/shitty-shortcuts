import AppKit

// Built-in config editor: dark, monospace, Lua syntax highlighting,
// Cmd+S saves and hot-reloads the config.
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    static var shared: EditorWindowController?

    private var textView: NSTextView!
    private var statusLabel: NSTextField!
    private var dirty = false
    private let path: String
    private let onSave: () -> Void

    // Solarized-ish dark palette
    private static let colBg = NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.12, alpha: 1)
    private static let colText = NSColor(calibratedWhite: 0.85, alpha: 1)
    private static let colKeyword = NSColor(calibratedRed: 0.78, green: 0.47, blue: 0.87, alpha: 1)
    private static let colString = NSColor(calibratedRed: 0.60, green: 0.80, blue: 0.45, alpha: 1)
    private static let colComment = NSColor(calibratedWhite: 0.45, alpha: 1)
    private static let colNumber = NSColor(calibratedRed: 0.95, green: 0.65, blue: 0.35, alpha: 1)
    private static let colCall = NSColor(calibratedRed: 0.40, green: 0.70, blue: 0.95, alpha: 1)

    static func open(path: String, onSave: @escaping () -> Void) {
        if let existing = shared {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = EditorWindowController(path: path, onSave: onSave)
        shared = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(path: String, onSave: @escaping () -> Void) {
        self.path = path
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "💩⌨️ " + (path as NSString).abbreviatingWithTildeInPath
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = EditorWindowController.colBg
        window.center()

        super.init(window: window)
        window.delegate = self

        // text view in scroll view
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = EditorWindowController.colBg

        let tv = NSTextView(frame: scroll.bounds)
        tv.autoresizingMask = [.width]
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = EditorWindowController.editorFont()
        tv.backgroundColor = EditorWindowController.colBg
        tv.textColor = EditorWindowController.colText
        tv.insertionPointColor = .white
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.textContainerInset = NSSize(width: 12, height: 12)
        tv.delegate = self
        textView = tv
        scroll.documentView = tv

        // status bar
        let status = NSTextField(labelWithString: "")
        status.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        status.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        status.frame = NSRect(x: 12, y: 4, width: 600, height: 16)
        status.autoresizingMask = [.width]
        statusLabel = status

        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        scroll.frame = NSRect(x: 0, y: 24, width: content.bounds.width, height: content.bounds.height - 24)
        let statusBar = NSView(frame: NSRect(x: 0, y: 0, width: content.bounds.width, height: 24))
        statusBar.autoresizingMask = [.width]
        statusBar.wantsLayer = true
        statusBar.layer?.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1).cgColor
        statusBar.addSubview(status)
        content.addSubview(scroll)
        content.addSubview(statusBar)
        window.contentView = content

        loadFile()
        installKeyMonitor()
        setStatus("⌘S save + reload · ⌘W close")
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func editorFont() -> NSFont {
        for name in ["JetBrains Mono", "Hack Nerd Font", "SF Mono", "Menlo"] {
            if let f = NSFont(name: name, size: 13) { return f }
        }
        return .monospacedSystemFont(ofSize: 13, weight: .regular)
    }

    private func loadFile() {
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        textView.string = text
        highlight()
        dirty = false
        updateTitle()
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try textView.string.write(toFile: path, atomically: true, encoding: .utf8)
            dirty = false
            updateTitle()
            onSave()
            setStatus("saved + reloaded ✓")
            return true
        } catch {
            setStatus("save failed: \(error.localizedDescription)")
            return false
        }
    }

    private func setStatus(_ s: String) { statusLabel.stringValue = s }

    private func updateTitle() {
        window?.title = "💩⌨️ " + (path as NSString).abbreviatingWithTildeInPath + (dirty ? " — edited" : "")
        window?.isDocumentEdited = dirty
    }

    // -- key handling --------------------------------------------------------

    private var keyMonitor: Any?

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods == .command {
                switch event.charactersIgnoringModifiers {
                case "s": self.save(); return nil
                case "w": self.window?.performClose(nil); return nil
                default: break
                }
            }
            return event
        }
    }

    @objc func saveAction(_ sender: Any?) { save() }

    func textDidChange(_ notification: Notification) {
        dirty = true
        updateTitle()
        highlight()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if dirty {
            let alert = NSAlert()
            alert.messageText = "Save changes to init.lua?"
            alert.addButton(withTitle: "Save & Reload")
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn: return save()
            case .alertSecondButtonReturn: return true
            default: return false
            }
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
        EditorWindowController.shared = nil
    }

    // -- syntax highlighting ---------------------------------------------------

    private static let luaKeywords = "\\b(and|break|do|else|elseif|end|false|for|function|goto|if|in|local|nil|not|or|repeat|return|then|true|until|while)\\b"

    private struct Rule {
        let regex: NSRegularExpression
        let color: NSColor
    }

    private static let rules: [Rule] = {
        func rule(_ pattern: String, _ color: NSColor) -> Rule {
            Rule(regex: try! NSRegularExpression(pattern: pattern, options: []), color: color)
        }
        return [
            rule("\\b\\d+\\.?\\d*\\b", colNumber),
            rule(luaKeywords, colKeyword),
            rule("\\b([%w_]*[a-zA-Z_][a-zA-Z0-9_]*)\\s*(?=\\()", colCall),
            rule("\"(?:[^\"\\\\]|\\\\.)*\"", colString),
            rule("'(?:[^'\\\\]|\\\\.)*'", colString),
            rule("--[^\\n]*", colComment),
        ]
    }()

    private func highlight() {
        guard let storage = textView.textStorage else { return }
        let text = textView.string as NSString
        let full = NSRange(location: 0, length: text.length)
        storage.beginEditing()
        storage.removeAttribute(.foregroundColor, range: full)
        storage.addAttribute(.foregroundColor, value: EditorWindowController.colText, range: full)
        for rule in EditorWindowController.rules {
            rule.regex.enumerateMatches(in: textView.string, options: [], range: full) { match, _, _ in
                if let r = match?.range {
                    storage.addAttribute(.foregroundColor, value: rule.color, range: r)
                }
            }
        }
        storage.endEditing()
    }
}
