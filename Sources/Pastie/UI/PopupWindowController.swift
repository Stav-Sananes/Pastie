// Sources/Pastie/UI/PopupWindowController.swift
import AppKit

final class PopupWindowController: NSObject, NSWindowDelegate {
    private let store: ClipStore
    private let pasteEngine: PasteEngine
    private var panel: NSPanel!
    private var searchField: NSSearchField!
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var allClips: [Clip] = []
    private var filteredClips: [Clip] = []

    init(store: ClipStore, pasteEngine: PasteEngine) {
        self.store = store
        self.pasteEngine = pasteEngine
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

        tableView = NSTableView(frame: .zero)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.width = 400
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = true
        tableView.target = self
        tableView.doubleAction = #selector(pasteSelection)

        scrollView = NSScrollView(frame: NSRect(x: 8, y: 8, width: 404, height: 304))
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true

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
        refresh()
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func refresh() {
        allClips = (try? store.fetchAll()) ?? []
        applyFilter()
    }

    private func applyFilter() {
        filteredClips = ClipSearch.filter(allClips, query: searchField.stringValue)
        tableView.reloadData()
    }

    @objc private func searchChanged() {
        applyFilter()
    }

    @objc private func pasteSelection() {
        let indexes = tableView.selectedRowIndexes
        guard !indexes.isEmpty else { return }
        let selection = indexes.map { filteredClips[$0] }
        let pasted = pasteEngine.paste(selection)
        hide()
        if !pasted {
            showAccessibilityFallbackAlert()
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
        guard row < filteredClips.count, let id = filteredClips[row].id else { return }
        try? store.setPinned(!filteredClips[row].pinned, id: id)
        refresh()
    }

    func deleteRow(at row: Int) {
        guard row < filteredClips.count, let id = filteredClips[row].id else { return }
        try? store.delete(id: id)
        refresh()
    }

    // NSWindowDelegate
    func windowDidResignKey(_ notification: Notification) {
        hide()
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
        switch clip.type {
        case .text: return clip.textContent ?? ""
        case .file: return "📄 " + (clip.filePath ?? "")
        case .image: return "🖼 Image (\((clip.imageData?.count ?? 0) / 1024) KB)"
        }
    }
}
