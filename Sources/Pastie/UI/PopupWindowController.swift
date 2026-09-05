// Sources/Pastie/UI/PopupWindowController.swift
import AppKit

final class PopupWindowController: NSObject, NSWindowDelegate {
    /// Non-list chrome (search field + hint row + margins) in buildPanel()'s base layout —
    /// total panel height minus the space given to the row list.
    static let chromeHeight: CGFloat = 72
    static let rowHeight: CGFloat = 24

    static func panelHeight(forRows rows: Int) -> CGFloat {
        chromeHeight + CGFloat(max(1, rows)) * rowHeight
    }

    /// One line in the popup's table: either a section title or a Clip. Headers are drawn but
    /// never selected — see tableView(_:shouldSelectRow:) and moveSelection(by:).
    enum Row {
        case header(String)
        case clip(Clip)
    }

    private let store: ClipStore
    private let pasteEngine: PasteEngine
    private let preferences: PreferencesStore
    private var panel: NSPanel!
    private var searchField: NSSearchField!
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var rows: [Row] = []
    private var savedClips: [Clip] = []
    private var historyClips: [Clip] = []
    /// The app that was frontmost right before Pastie activated itself, so paste(_:plain:)
    /// can hand focus back to it before simulating ⌘V.
    private var previousApp: NSRunningApplication?
    /// Local key-down monitor active while the panel is visible, so Return/Escape work
    /// regardless of which control (search field or table view) currently has focus.
    private var keyMonitor: Any?
    /// Told to ignore the pasteboard change caused by our own paste-as-list writes, so
    /// ClipboardMonitor.tick() doesn't re-capture what we just pasted as a brand-new clip.
    weak var clipboardMonitor: ClipboardMonitor?
    /// Fired whenever a slot binding may have changed, so AppDelegate can re-register the global
    /// slot hotkeys.
    var onSlotsChanged: (() -> Void)?

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
            styleMask: [.titled, .closable, .nonactivatingPanel, .resizable],
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

        // A keyboard-first app whose keys are undocumented is a keyboard-hostile app.
        let hint = NSTextField(labelWithString: "↵ paste · ⇧↵ plain · ⌘1–9 quick · ⌘T transform · ⌘E edit")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 8, y: 300, width: 404, height: 14)
        hint.autoresizingMask = [.width, .minYMargin]

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

        scrollView = NSScrollView(frame: NSRect(x: 8, y: 8, width: 404, height: 288))
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        panel.contentView?.addSubview(searchField)
        panel.contentView?.addSubview(hint)
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
    /// event monitor catches the popup's keys regardless of first responder, without disturbing
    /// the existing doCommandBy: arrow-key/Return/Escape forwarding used while typing.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let command = event.modifierFlags.contains(.command)
            let shift = event.modifierFlags.contains(.shift)

            switch event.keyCode {
            case 36 where shift:            // ⇧Return — paste without formatting
                self.pasteSelectionPlain()
                return nil
            case 36:                        // Return
                self.pasteSelection()
                return nil
            case 53:                        // Escape
                self.hide()
                return nil
            default:
                break
            }

            guard command, let characters = event.charactersIgnoringModifiers else { return event }
            switch characters {
            case "1"..."9":
                if let digit = Int(characters) { self.pasteVisibleRow(number: digit) }
                return nil
            case "t":
                self.showTransformMenu()
                return nil
            case "e":
                self.showEditSheet()
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
        savedClips = (try? store.saved()) ?? []
        historyClips = (try? store.history()) ?? []
        applyFilter()
    }

    private func applyFilter() {
        let query = searchField.stringValue
        let saved = ClipSearch.filter(savedClips, query: query)
        let history = ClipSearch.filter(historyClips, query: query)
        var built: [Row] = []
        if !saved.isEmpty {
            built.append(.header("Saved"))
            built.append(contentsOf: saved.map { Row.clip($0) })
        }
        if !history.isEmpty {
            built.append(.header("History"))
            built.append(contentsOf: history.map { Row.clip($0) })
        }
        rows = built
        tableView.reloadData()
        selectFirstSelectableRow()
    }

    private func selectFirstSelectableRow() {
        guard let index = rows.firstIndex(where: { if case .clip = $0 { return true } else { return false } }) else { return }
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }

    private func clip(at row: Int) -> Clip? {
        guard row >= 0, row < rows.count, case let .clip(clip) = rows[row] else { return nil }
        return clip
    }

    private var selectedClips: [Clip] {
        tableView.selectedRowIndexes.compactMap { clip(at: $0) }
    }

    @objc private func searchChanged() {
        applyFilter()
    }

    private func moveSelection(by delta: Int) {
        guard !rows.isEmpty else { return }
        var next = tableView.selectedRow < 0 ? 0 : tableView.selectedRow + delta
        while next >= 0, next < rows.count, clip(at: next) == nil {
            next += delta   // step over the section header
        }
        guard next >= 0, next < rows.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func pasteSelection() {
        paste(selectedClips, plain: false)
    }

    @objc private func pasteSelectionPlain() {
        paste(selectedClips, plain: true)
    }

    private func paste(_ clips: [Clip], plain: Bool) {
        guard !clips.isEmpty else { return }

        // Hide Pastie and hand focus back to whatever app the user was in BEFORE simulating
        // ⌘V — otherwise the keystroke goes to the still-key Pastie panel instead of the
        // target app. Give the target app's focus a moment to settle before pasting.
        hide()
        previousApp?.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            let pasted = self.pasteEngine.paste(clips, plain: plain, beforeEachWrite: { [weak self] in
                self?.clipboardMonitor?.ignoreNextChange()
            })
            if !pasted {
                self.showAccessibilityFallbackAlert()
            }
        }
    }

    /// ⌘1–9 inside the popup pastes the Nth *visible clip row* — what the user can see and count,
    /// which is not the same as a quick-paste slot binding.
    private func pasteVisibleRow(number: Int) {
        let clips = rows.compactMap { row -> Clip? in
            if case let .clip(clip) = row { return clip } else { return nil }
        }
        guard number >= 1, number <= clips.count else { return }
        paste([clips[number - 1]], plain: false)
    }

    private func showTransformMenu() {
        guard let clip = selectedClips.first, clip.type == .text, let text = clip.textContent else {
            NSSound.beep()
            return
        }
        let menu = NSMenu(title: "Transform")
        for transform in TransformRegistry.all {
            let item = menu.addItem(withTitle: transform.name, action: #selector(applyTransform(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = TransformInvocation(transform: transform, input: text)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 8, y: panel.frame.height - 60), in: panel.contentView)
    }

    /// Carries a chosen transform and the text it was chosen for from the menu item to the action.
    private final class TransformInvocation: NSObject {
        let transform: any Transform
        let input: String
        init(transform: any Transform, input: String) {
            self.transform = transform
            self.input = input
        }
    }

    @objc private func applyTransform(_ sender: NSMenuItem) {
        guard let invocation = sender.representedObject as? TransformInvocation else { return }
        guard let output = invocation.transform.apply(invocation.input) else {
            let alert = NSAlert()
            alert.messageText = "\(invocation.transform.name) couldn't be applied"
            alert.informativeText = "The selected clip isn't valid input for this transform."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        pasteTransientText(output)
    }

    private func showEditSheet() {
        guard let clip = selectedClips.first, clip.type == .text, let text = clip.textContent else {
            NSSound.beep()
            return
        }
        ClipEditSheet.present(text: text, in: panel) { [weak self] edited in
            guard let self, let edited else { return }
            self.pasteTransientText(edited)
        }
    }

    /// Pastes text that is not a stored clip — a transform result or an edited copy. Nothing is
    /// written to the store: Transforms and edits never modify History.
    private func pasteTransientText(_ text: String) {
        let transient = Clip(id: nil, type: .text, textContent: text, imageData: nil, filePath: nil, sourceApp: nil, timestamp: Date(), saved: false, sortOrder: 0)
        paste([transient], plain: true)
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

    // Right-click context menu — the only way to reach Save/Assign to Slot/Delete from the UI.
    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Save", action: #selector(toggleSavedFromMenu), keyEquivalent: "").target = self

        let slotItem = menu.addItem(withTitle: "Assign to Slot", action: nil, keyEquivalent: "")
        let slotMenu = NSMenu()
        for slot in ClipStore.slotRange {
            let item = slotMenu.addItem(withTitle: "Slot \(slot)", action: #selector(assignSlotFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.tag = slot
        }
        let clear = slotMenu.addItem(withTitle: "None", action: #selector(assignSlotFromMenu(_:)), keyEquivalent: "")
        clear.target = self
        clear.tag = 0            // tag 0 means "unbind"
        slotItem.submenu = slotMenu

        menu.addItem(withTitle: "Delete", action: #selector(deleteFromMenu), keyEquivalent: "").target = self
        return menu
    }

    @objc private func assignSlotFromMenu(_ sender: NSMenuItem) {
        guard let id = clip(at: tableView.clickedRow)?.id else { return }
        try? store.assignSlot(sender.tag == 0 ? nil : sender.tag, id: id)
        refresh()
        onSlotsChanged?()
    }

    @objc private func toggleSavedFromMenu() {
        guard let clip = clip(at: tableView.clickedRow), let id = clip.id else { return }
        try? store.setSaved(!clip.saved, id: id)
        refresh()
        onSlotsChanged?()
    }

    @objc private func deleteFromMenu() {
        guard let id = clip(at: tableView.clickedRow)?.id else { return }
        try? store.delete(id: id)
        refresh()
        onSlotsChanged?()
    }

    // NSWindowDelegate
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    /// The title bar's close button. Routed through hide() rather than letting the panel close
    /// itself, so the local key monitor is torn down the same way Esc tears it down — and the
    /// panel is kept alive to be shown again, instead of being released.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
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
        let clicked = clip(at: tableView.clickedRow)
        for item in menu.items {
            item.isEnabled = clicked != nil
            if item.action == #selector(toggleSavedFromMenu) {
                item.title = (clicked?.saved ?? false) ? "Unsave" : "Save"
            }
        }
    }
}

extension PopupWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        clip(at: row) != nil
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case let .header(title):
            let cell = NSTextField(labelWithString: title.uppercased())
            cell.font = .systemFont(ofSize: 10, weight: .semibold)
            cell.textColor = .secondaryLabelColor
            return cell
        case let .clip(clip):
            let cell = NSTextField(labelWithString: displayText(for: clip))
            cell.lineBreakMode = .byTruncatingTail
            return cell
        }
    }

    private func displayText(for clip: Clip) -> String {
        let slot = clip.slotIndex.map { "⌘\($0) " } ?? ""
        let kept = clip.saved ? "★ " : ""
        switch clip.type {
        case .text: return slot + kept + (clip.textContent ?? "")
        case .file: return slot + kept + "📄 " + (clip.filePath ?? "")
        case .image: return slot + kept + "🖼 Image (\((clip.imageData?.count ?? 0) / 1024) KB)"
        }
    }
}
