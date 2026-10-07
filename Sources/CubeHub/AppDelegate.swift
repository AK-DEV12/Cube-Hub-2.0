import AppKit
import ServiceManagement
import SwiftUI
import CubeHubCore

/// Borderless windows refuse keyboard focus unless told otherwise, and the
/// timer needs the space bar.
final class WidgetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct LaunchOptions {
    /// Use this solves file instead of the one in Application Support.
    var dataURL: URL?
    /// Render the widget in each timer state to PNGs in this folder, then quit.
    var snapshotDirectory: URL?
    /// Write the app icon as a 1024px PNG to this path, then quit.
    var iconURL: URL?

    init(arguments: [String]) {
        var remaining = arguments.dropFirst()
        while let flag = remaining.popFirst() {
            guard let value = remaining.popFirst() else { break }
            let url = URL(fileURLWithPath: value)
            switch flag {
            case "--data": dataURL = url
            case "--snapshot": snapshotDirectory = url
            case "--icon": iconURL = url
            default: break
            }
        }
    }
}

/// Cube Hub lives in the menu bar: clicking its icon shows or hides the widget.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private static let frameName = "CubeHubWidget.v3"
    private static let spaceKey: UInt16 = 49
    private static let escapeKey: UInt16 = 53
    private static let deleteKey: UInt16 = 51
    private static let sizeStep: CGFloat = 0.1

    private let options: LaunchOptions
    private var storeURL: URL!
    private var window: WidgetWindow!
    private var model: TimerModel!
    private var statusItem: NSStatusItem?
    private var keyMonitor: Any?
    /// Where the pointer and the window were when the current move or resize began.
    private var dragStart: (pointer: NSPoint, frame: NSRect)?

    init(options: LaunchOptions) {
        self.options = options
    }

    private var isSnapshotRun: Bool { options.snapshotDirectory != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let dataURL = options.dataURL {
            storeURL = dataURL
        } else if isSnapshotRun {
            storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("cubehub-snapshot-\(UUID().uuidString).json")
        } else {
            storeURL = SolveStore.defaultURL()
        }
        let store = SolveStore(url: storeURL)
        // Snapshots get sample history unless a solves file was named explicitly.
        if isSnapshotRun && options.dataURL == nil {
            Snapshots.seed(store)
        }
        model = TimerModel(store: store, persistsPreferences: !isSnapshotRun)
        model.onAlwaysOnTopChange = { [weak self] _ in self?.applyWindowLevel() }

        // No Dock icon; the menu bar item is the way in.
        NSApp.setActivationPolicy(.accessory)
        if !isSnapshotRun {
            makeStatusItem()
        }
        makeWindow()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }

        if let directory = options.snapshotDirectory {
            // Snapshot runs stay out of the way: nothing in the menu bar, no keyboard focus.
            window.orderFrontRegardless()
            Snapshots.run(model: model, window: window, into: directory)
        } else {
            showWidget()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening the app again while it's running brings the widget back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWidget()
        return true
    }

    // MARK: - Menu bar

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MascotSprite.menuBarImage()
        item.button?.toolTip = "Cube Hub"
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    /// Click toggles the widget; right-click (or control-click) opens the menu.
    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            guard let statusItem else { return }
            statusItem.menu = makeMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            toggleWidget(nil)
        }
    }

    private var isWidgetShowing: Bool {
        window.isVisible && window.occlusionState.contains(.visible)
    }

    private func showWidget() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func hideWidget() {
        model.cancel()
        window.orderOut(nil)
        // Hands keyboard focus back to whichever app was in front before.
        NSApp.hide(nil)
    }

    @objc private func toggleWidget(_ sender: Any?) {
        if isWidgetShowing {
            hideWidget()
        } else {
            showWidget()
        }
    }

    // MARK: - Window

    private func makeWindow() {
        let actions = WidgetActions(
            showMenu: { [weak self] in self?.popUpMenu() },
            move: { [weak self] phase in self?.moveDragged(phase) },
            resize: { [weak self] phase in self?.resizeDragged(phase) }
        )
        let host = NSHostingView(rootView: WidgetView(model: model, actions: actions))
        // The window's size is ours to manage; the content fills whatever it's given.
        host.sizingOptions = []

        let defaultSize = NSSize(
            width: WidgetLayout.baseWidth * WidgetLayout.defaultScale,
            height: WidgetLayout.defaultBaseHeight * WidgetLayout.defaultScale
        )
        window = WidgetWindow(contentRect: NSRect(origin: .zero, size: defaultSize), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.isOpaque = false
        window.backgroundColor = .clear
        // The card draws its own shadow; a window shadow would smear behind the animated mascot.
        window.hasShadow = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        applyWindowLevel()

        // Forced, because a borderless window otherwise gets back only its position, not its size.
        if !isSnapshotRun, window.setFrameUsingName(Self.frameName, force: true),
           NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
            // Re-apply the limits in case the screen changed since last time.
            setFrame(topLeft: NSPoint(x: window.frame.minX, y: window.frame.maxY), width: window.frame.width, height: window.frame.height)
        } else {
            setFrame(topLeft: defaultTopLeft(for: defaultSize), width: defaultSize.width, height: defaultSize.height)
        }
        if !isSnapshotRun {
            window.setFrameAutosaveName(Self.frameName)
        }
    }

    /// The top right corner, with the card touching the menu bar.
    private func defaultTopLeft(for size: NSSize) -> NSPoint {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.maxX - size.width, y: visible.maxY)
    }

    private var currentScale: CGFloat {
        window.frame.width / WidgetLayout.baseWidth
    }

    /// Width sets the scale of everything; height beyond the minimum shows more solves.
    private func setFrame(topLeft: NSPoint, width: CGFloat, height: CGFloat) {
        let screenHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? .greatestFiniteMagnitude
        let largestScale = max(WidgetLayout.scaleRange.lowerBound, min(WidgetLayout.scaleRange.upperBound, screenHeight / WidgetLayout.minBaseHeight))
        let scale = min(max(width / WidgetLayout.baseWidth, WidgetLayout.scaleRange.lowerBound), largestScale)
        let minHeight = scale * WidgetLayout.minBaseHeight
        let maxHeight = max(minHeight, min(screenHeight, scale * WidgetLayout.maxBaseHeight))
        let clampedHeight = min(max(height, minHeight), maxHeight)
        window.setFrame(
            NSRect(x: topLeft.x, y: topLeft.y - clampedHeight, width: scale * WidgetLayout.baseWidth, height: clampedHeight),
            display: true
        )
    }

    /// Scales the whole widget, keeping its proportions and its top left corner.
    private func setScale(_ requested: CGFloat) {
        // Window frames land on whole points, so snap to keep steps from drifting.
        let scale = (requested * 20).rounded() / 20
        let frame = window.frame
        let baseHeight = frame.height / currentScale
        setFrame(topLeft: NSPoint(x: frame.minX, y: frame.maxY), width: scale * WidgetLayout.baseWidth, height: scale * baseHeight)
        saveFrame()
    }

    private var pointerLocation: NSPoint {
        // Snapshot runs steer with posted events; the real pointer is somewhere else.
        if isSnapshotRun, let event = NSApp.currentEvent {
            return window.convertPoint(toScreen: event.locationInWindow)
        }
        return NSEvent.mouseLocation
    }

    private func resizeDragged(_ phase: DragPhase) {
        switch phase {
        case .changed:
            let pointer = pointerLocation
            let start = dragStart ?? (pointer, window.frame)
            dragStart = start
            setFrame(
                topLeft: NSPoint(x: start.frame.minX, y: start.frame.maxY),
                width: start.frame.width + pointer.x - start.pointer.x,
                height: start.frame.height + start.pointer.y - pointer.y
            )
        case .ended:
            dragStart = nil
            saveFrame()
        }
    }

    /// Follows the pointer, stopping flush under the menu bar and never leaving the screen entirely.
    private func moveDragged(_ phase: DragPhase) {
        switch phase {
        case .changed:
            let pointer = pointerLocation
            let start = dragStart ?? (pointer, window.frame)
            dragStart = start
            var origin = NSPoint(
                x: start.frame.minX + pointer.x - start.pointer.x,
                y: start.frame.minY + pointer.y - start.pointer.y
            )
            let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? window.screen ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                let size = start.frame.size
                let reach: CGFloat = 60
                let cardLeft = WidgetLayout.gutter * currentScale
                let cardRight = size.width - WidgetLayout.margin * currentScale
                origin.x = min(max(origin.x, visible.minX + reach - cardRight), visible.maxX - reach - cardLeft)
                origin.y = min(max(origin.y, visible.minY + reach - size.height), visible.maxY - size.height)
            }
            window.setFrameOrigin(origin)
        case .ended:
            dragStart = nil
            saveFrame()
        }
    }

    private func saveFrame() {
        guard !isSnapshotRun else { return }
        window.saveFrame(usingName: Self.frameName)
    }

    private func applyWindowLevel() {
        window.level = model.alwaysOnTop ? .floating : .normal
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.setFocused(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        model.setFocused(false)
    }

    // MARK: - Keyboard

    /// Space and escape drive the timer; ⌘ shortcuts mirror the menu.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard event.window === window else { return event }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        if modifiers == .command {
            return event.type == .keyDown && handleShortcut(event) ? nil : event
        }
        guard modifiers.isEmpty else { return event }

        switch (event.type, event.keyCode) {
        case (.keyDown, Self.spaceKey):
            // With a panel open over the card, space is left alone.
            if !event.isARepeat && model.sheet == nil {
                model.spaceDown(at: event.timestamp)
            }
            return nil
        case (.keyUp, Self.spaceKey):
            model.spaceUp(at: event.timestamp)
            return nil
        case (.keyDown, Self.escapeKey):
            return model.cancel() ? nil : event
        default:
            return event
        }
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        if event.keyCode == Self.deleteKey {
            deleteLastSolve(nil)
            return true
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "2": model.selectPuzzle(.two)
        case "3": model.selectPuzzle(.three)
        case "4": model.selectPuzzle(.four)
        case "r": newScramble(nil)
        case "t": toggleAlwaysOnTop(nil)
        case "=", "+": makeBigger(nil)
        case "-": makeSmaller(nil)
        case "w": hideWidget()
        case "q": NSApp.terminate(nil)
        default: return false
        }
        return true
    }

    // MARK: - Menu

    private func popUpMenu() {
        makeMenu().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Shared by the menu bar icon and the widget's "…" button.
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: isWidgetShowing ? "Hide Cube Hub" : "Show Cube Hub", action: #selector(toggleWidget(_:)), keyEquivalent: isWidgetShowing ? "w" : "")
        menu.addItem(.separator())

        let puzzles = NSMenu()
        for puzzle in Puzzle.allCases {
            let item = puzzles.addItem(withTitle: puzzle.rawValue, action: #selector(choosePuzzle(_:)), keyEquivalent: "\(puzzle.size)")
            item.representedObject = puzzle.rawValue
        }
        let puzzleItem = menu.addItem(withTitle: "Puzzle", action: nil, keyEquivalent: "")
        puzzleItem.submenu = puzzles

        menu.addItem(withTitle: "New Scramble", action: #selector(newScramble(_:)), keyEquivalent: "r")
        menu.addItem(withTitle: "Delete Last Solve", action: #selector(deleteLastSolve(_:)), keyEquivalent: "\u{8}")
        menu.addItem(withTitle: "Clear All \(model.puzzle.rawValue) Solves…", action: #selector(clearAllSolves(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Keep on Top", action: #selector(toggleAlwaysOnTop(_:)), keyEquivalent: "t")

        let size = NSMenu()
        size.addItem(withTitle: "Bigger", action: #selector(makeBigger(_:)), keyEquivalent: "=")
        size.addItem(withTitle: "Smaller", action: #selector(makeSmaller(_:)), keyEquivalent: "-")
        size.addItem(.separator())
        for (title, scale) in [("Small", 1.0), ("Medium", 1.2), ("Large", 1.5)] {
            let item = size.addItem(withTitle: title, action: #selector(chooseSize(_:)), keyEquivalent: "")
            item.representedObject = scale
        }
        let sizeItem = menu.addItem(withTitle: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = size

        menu.addItem(.separator())
        menu.addItem(withTitle: "Show Solves File in Finder", action: #selector(showSolvesFile(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Open at Login", action: #selector(toggleOpenAtLogin(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Cube Hub", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        for item in menu.items + puzzles.items + size.items where item.action != #selector(NSApplication.terminate(_:)) && item.action != nil {
            item.target = self
        }
        return menu
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleAlwaysOnTop(_:)):
            menuItem.state = model.alwaysOnTop ? .on : .off
            return true
        case #selector(toggleOpenAtLogin(_:)):
            menuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
            return true
        case #selector(chooseSize(_:)):
            let scale = menuItem.representedObject as? Double ?? 0
            menuItem.state = abs(currentScale - scale) < 0.01 ? .on : .off
            return true
        case #selector(choosePuzzle(_:)):
            menuItem.state = menuItem.representedObject as? String == model.puzzle.rawValue ? .on : .off
            return model.phase == .idle
        case #selector(newScramble(_:)):
            return model.phase == .idle
        case #selector(deleteLastSolve(_:)), #selector(clearAllSolves(_:)):
            return model.phase == .idle && !model.solves.isEmpty
        default:
            return true
        }
    }

    @objc private func choosePuzzle(_ sender: NSMenuItem) {
        guard let puzzle = (sender.representedObject as? String).flatMap(Puzzle.init(rawValue:)) else { return }
        model.selectPuzzle(puzzle)
    }

    @objc private func newScramble(_ sender: Any?) {
        model.newScramble()
    }

    @objc private func deleteLastSolve(_ sender: Any?) {
        model.deleteLast()
    }

    @objc private func toggleAlwaysOnTop(_ sender: Any?) {
        model.alwaysOnTop.toggle()
    }

    @objc private func makeBigger(_ sender: Any?) {
        setScale(currentScale + Self.sizeStep)
    }

    @objc private func makeSmaller(_ sender: Any?) {
        setScale(currentScale - Self.sizeStep)
    }

    @objc private func chooseSize(_ sender: NSMenuItem) {
        guard let scale = sender.representedObject as? Double else { return }
        setScale(scale)
    }

    @objc private func showSolvesFile(_ sender: Any?) {
        if FileManager.default.fileExists(atPath: storeURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([storeURL])
        } else {
            // Nothing saved yet: show where the file will appear.
            let folder = storeURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        }
    }

    @objc private func toggleOpenAtLogin(_ sender: Any?) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nYou can also add Cube Hub under System Settings › General › Login Items."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func clearAllSolves(_ sender: Any?) {
        guard model.phase == .idle, !model.solves.isEmpty else { return }
        let count = model.solves.count
        let alert = NSAlert()
        alert.alertStyle = .warning
        let puzzle = model.puzzle.rawValue
        alert.messageText = count == 1 ? "Delete your \(puzzle) solve?" : "Delete all \(count) \(puzzle) solves?"
        alert.informativeText = "Your \(puzzle) times, averages and bests will be erased. Other puzzles keep theirs. This can't be undone."
        alert.addButton(withTitle: "Delete All").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            model.clearAll()
        }
    }
}
