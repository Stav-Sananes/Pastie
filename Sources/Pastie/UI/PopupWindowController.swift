// Sources/Pastie/UI/PopupWindowController.swift
import AppKit

final class PopupWindowController: NSObject, NSWindowDelegate {
    /// Non-list chrome (search field + margins) in buildPanel()'s base layout — total
    /// panel height minus the space given to the row list.
    static let chromeHeight: CGFloat = 56
    static let rowHeight: CGFloat = 24

    static func panelHeight(forRows rows: Int) -> CGFloat {
        chromeHeight + CGFloat(max(1, rows)) * rowHeight
    }

    private let store: ClipStore
    private let pasteEngine: PasteEngine
    private let preferences: PreferencesStore
    private var panel: NSPanel!
    private var searchField: NSSearchField!
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var allClips: [Clip] = []
    private var filteredClips: [Clip] = []
    /// The app that was frontmost right before Pastie activated itself, so pasteSelection()
    /// can hand focus back to it before simulating ⌘V.
    private var previousApp: NSRunningApplication?
    /// Local key-down monitor active while the panel is visible, so Return/Escape work
    /// regardless of which control (search field or table view) currently has focus.
    private var keyMonitor: Any?
    /// Told to ignore the pasteboard change caused by our own paste-as-list writes, so
    /// ClipboardMonitor.tick() doesn't re-capture what we just pasted as a brand-new clip.
    weak var clipboardMonitor: ClipboardMonitor?

    init(store: ClipStore, pasteEngine: PasteEngine, preferences: PreferencesStore) {
        self.store = store
        self.pasteEngine = pasteEngine
        self.preferences = preferences
        super.init()
        buildPanel()
    }

    private func buildPanel() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.delegate = self
        panel.title = "Pastie"

        searchField = NSSearchField(frame: NSRect(x: 8, y: 320, width: 404, height: 24))
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.delegate = self
        searchField.autoresizingMask = [.width, .minYMargin]

        tableView = NSTableView(frame: .zero)
        tableView.rowHeight = Self.rowHeight
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.width = 400
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = true
        tableView.target = self
        tableView.doubleAction = #selector(pasteSelection)
        tableView.menu = buildContextMenu()

        scrollView = NSScrollView(frame: NSRect(x: 8, y: 8, width: 404, height: 304))
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        panel.contentView?.addSubview(searchField)
        panel.contentView?.addSubview(scrollView)
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        refresh()
        panel.setContentSize(NSSize(width: panel.frame.width, height: Self.panelHeight(forRows: preferences.popupRowCount)))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitor()
    }

    func hide() {
        panel.orderOut(nil)
        removeKeyMonitor()
    }

    /// The panel's actual content-view height. Exposed (internal, not private) so tests
    /// can verify `show()` sizes the panel via content size rather than window-frame size —
    /// see PopupWindowControllerTests.testShowSetsContentHeightToPanelHeightForConfiguredRowCount.
    var currentContentHeightForTesting: CGFloat? {
        panel.contentView?.frame.height
    }

    /// The table view's actual configured row height — exposed so tests can verify it
    /// matches `Self.rowHeight`, the per-row height `panelHeight(forRows:)` assumes.
    var tableRowHeightForTesting: CGFloat {
        tableView.rowHeight
    }

    /// Enter/Esc need to work no matter which control has focus — doCommandBy: on the search
    /// field's delegate only fires while focus is IN the search field, but clicking a row (the
    /// only way to ⌘/⇧-click multi-select) moves first responder to the table view. A local
    /// event monitor catches Return/Escape regardless of first responder, without disturbing
    /// the existing doCommandBy: arrow-key/Return/Escape forwarding used while typing.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 36: // Return
                self.pasteSelection()
                return nil
            case 53: // Escape
                self.hide()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func refresh() {
        allClips = (try? store.fetchAll()) ?? []
        applyFilter()
    }

    private func applyFilter() {
        filteredClips = ClipSearch.filter(allClips, query: searchField.stringValue)
        tableView.reloadData()
        if !filteredClips.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    @objc private func searchChanged() {
        applyFilter()
    }

    private func moveSelection(by delta: Int) {
        guard !filteredClips.isEmpty else { return }
        let current = tableView.selectedRow
        let next = current < 0 ? 0 : max(0, min(filteredClips.count - 1, current + delta))
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func pasteSelection() {
        let indexes = tableView.selectedRowIndexes
        guard !indexes.isEmpty else { return }
        let selection = indexes.map { filteredClips[$0] }

        // Hide Pastie and hand focus back to whatever app the user was in BEFORE simulating
        // ⌘V — otherwise the keystroke goes to the still-key Pastie panel instead of the
        // target app. Give the target app's focus a moment to settle before pasting.
        hide()
        previousApp?.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            let pasted = self.pasteEngine.paste(selection, beforeEachWrite: { [weak self] in
                self?.clipboardMonitor?.ignoreNextChange()
            })
            if !pasted {
                self.showAccessibilityFallbackAlert()
            }
        }
    }

    private func showAccessibilityFallbackAlert() {
        let alert = NSAlert()
        alert.messageText = "Copied to Clipboard"
        alert.informativeText = "Pastie needs Accessibility permission to paste automatically. The content is on your clipboard — press ⌘V to paste manually, or grant permission in System Settings → Privacy & Security → Accessibility."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open System Settings")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    func togglePin(at row: Int) {
        guard row >= 0, row < filteredClips.count, let id = filteredClips[row].id else { return }
        try? store.setPinned(!filteredClips[row].pinned, id: id)
        refresh()
    }

    func deleteRow(at row: Int) {
        guard row >= 0, row < filteredClips.count, let id = filteredClips[row].id else { return }
        try? store.delete(id: id)
        refresh()
    }

    // Right-click context menu — the only way to reach togglePin/deleteRow from the UI.
    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Pin", action: #selector(togglePinFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Delete", action: #selector(deleteFromMenu), keyEquivalent: "").target = self
        return menu
    }

    @objc private func togglePinFromMenu() {
        togglePin(at: tableView.clickedRow)
    }

    @objc private func deleteFromMenu() {
        deleteRow(at: tableView.clickedRow)
    }

    // NSWindowDelegate
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

extension PopupWindowController: NSSearchFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            pasteSelection()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        default:
            return false
        }
    }
}

extension PopupWindowController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let row = tableView.clickedRow
        let validRow = row >= 0 && row < filteredClips.count
        let pinned = validRow && filteredClips[row].pinned
        for item in menu.items {
            item.isEnabled = validRow
            if item.action == #selector(togglePinFromMenu) {
                item.title = pinned ? "Unpin" : "Pin"
            }
        }
    }
}

extension PopupWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredClips.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let clip = filteredClips[row]
        let cell = NSTextField(labelWithString: displayText(for: clip))
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }

    private func displayText(for clip: Clip) -> String {
        let pinPrefix = clip.pinned ? "📌 " : ""
        switch clip.type {
        case .text: return pinPrefix + (clip.textContent ?? "")
        case .file: return pinPrefix + "📄 " + (clip.filePath ?? "")
        case .image: return pinPrefix + "🖼 Image (\((clip.imageData?.count ?? 0) / 1024) KB)"
        }
    }
}
