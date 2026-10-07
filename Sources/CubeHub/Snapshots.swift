import AppKit
import SwiftUI
import CubeHubCore

/// Renders the icon, and the widget in each timer state, to PNGs — used by the
/// build script and for checking the design without driving the keyboard.
@MainActor
enum Snapshots {
    static func writeIcon(to url: URL) -> Bool {
        let renderer = ImageRenderer(content: IconView())
        renderer.scale = 1
        guard let image = renderer.cgImage else { return false }
        return write(NSBitmapImageRep(cgImage: image), to: url)
    }

    static func seed(_ store: SolveStore) {
        let times = [2231, 1987, 2105, 1844, 2390, 1762, 1915, 2048, 1699, 1880, 2512, 1803, 1731, 1958]
        for (offset, centis) in times.enumerated() {
            let date = Date().addingTimeInterval(TimeInterval(offset - times.count) * 90)
            store.add(Solve(centis: centis, scramble: Scrambler.generate(), date: date))
        }
    }

    static func run(model: TimerModel, window: NSWindow, into directory: URL) {
        func pause(_ seconds: TimeInterval) async { try? await Task.sleep(for: .seconds(seconds)) }
        func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
        // Posted to the event queue, so input goes through the same handlers as a real keyboard and mouse.
        func key(_ type: NSEvent.EventType, _ characters: String = " ", code: UInt16 = 49, command: Bool = false, isRepeat: Bool = false) {
            guard let event = NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: command ? .command : [],
                timestamp: now(),
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: isRepeat,
                keyCode: code
            ) else { return }
            NSApp.postEvent(event, atStart: false)
        }
        func mouse(_ type: NSEvent.EventType, atScreenPoint point: NSPoint) {
            guard let event = NSEvent.mouseEvent(
                with: type,
                location: window.convertPoint(fromScreen: point),
                modifierFlags: [],
                timestamp: now(),
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            ) else { return }
            NSApp.postEvent(event, atStart: false)
        }
        func capture(_ name: String) {
            guard let view = window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            _ = write(bitmap, to: directory.appendingPathComponent("\(name).png"))
        }
        func report(_ label: String) {
            let frame = window.frame
            print("\(label): \(Int(frame.width))x\(Int(frame.height)) scale \(String(format: "%.2f", frame.width / WidgetLayout.baseWidth)) top-left (\(Int(frame.minX)), \(Int(frame.maxY)))")
        }

        Task {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            writeMenuBarIcon(to: directory.appendingPathComponent("menu-bar-icon.png"))
            await pause(0.8)
            report("launch")
            print("scramble: \(model.scramble)")
            capture("1-idle")
            // A tap that's let go too early must not start the timer.
            key(.keyDown)
            await pause(0.1)
            key(.keyUp)
            await pause(0.1)
            key(.keyDown)
            await pause(0.15)
            capture("2-holding")
            key(.keyDown, isRepeat: true)
            await pause(0.4)
            capture("3-ready")
            key(.keyUp)
            await pause(1.25)
            capture("4-running")
            // Faster than every seeded solve, so this one is a new best.
            key(.keyDown)
            await pause(0.05)
            key(.keyDown, isRepeat: true)
            key(.keyUp)
            await pause(0.5)
            capture("5-new-best")
            await pause(5.2)
            capture("6-settled")

            key(.keyDown, "-", code: 27, command: true)
            key(.keyDown, "-", code: 27, command: true)
            await pause(0.4)
            report("after ⌘- twice")
            capture("7-smaller")

            // Drag the resize grip: 90 points wider, 60 points taller.
            let scale = window.frame.width / WidgetLayout.baseWidth
            let inset = (WidgetLayout.margin + 15) * scale
            let grip = NSPoint(x: window.frame.maxX - inset, y: window.frame.minY + inset)
            mouse(.leftMouseDown, atScreenPoint: grip)
            await pause(0.1)
            for step in 1...6 {
                let travel = CGFloat(step) / 6
                mouse(.leftMouseDragged, atScreenPoint: NSPoint(x: grip.x + 90 * travel, y: grip.y - 60 * travel))
                await pause(0.05)
            }
            mouse(.leftMouseUp, atScreenPoint: NSPoint(x: grip.x + 90, y: grip.y - 60))
            await pause(0.4)
            report("after dragging the grip +90, +60")
            capture("8-resized")

            @MainActor func drag(from start: NSPoint, by offset: NSPoint) async {
                mouse(.leftMouseDown, atScreenPoint: start)
                await pause(0.1)
                for step in 1...6 {
                    let travel = CGFloat(step) / 6
                    mouse(.leftMouseDragged, atScreenPoint: NSPoint(x: start.x + offset.x * travel, y: start.y + offset.y * travel))
                    await pause(0.05)
                }
                mouse(.leftMouseUp, atScreenPoint: NSPoint(x: start.x + offset.x, y: start.y + offset.y))
                await pause(0.3)
            }
            // Pick the card up by the timer digits, which sit inside the scrolling page.
            @MainActor func timerDigits() -> NSPoint {
                let scale = window.frame.width / WidgetLayout.baseWidth
                return NSPoint(x: window.frame.minX + (WidgetLayout.gutter + WidgetLayout.cardWidth / 2) * scale, y: window.frame.maxY - 150 * scale)
            }
            await drag(from: timerDigits(), by: NSPoint(x: -150, y: -80))
            report("after dragging the card -150, -80")
            await drag(from: timerDigits(), by: NSPoint(x: 0, y: 600))
            report("after dragging the card up past the menu bar (screen top \(Int(window.screen?.visibleFrame.maxY ?? 0)))")

            // Scroll the page down, then start a hold: the timer should come back into view.
            @MainActor func scrollViews(in view: NSView) -> [NSScrollView] {
                (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
            }
            if let scrollView = scrollViews(in: window.contentView!).first {
                let clip = scrollView.contentView
                print("page: \(Int(scrollView.documentView?.frame.height ?? 0)) tall in a \(Int(clip.bounds.height)) viewport")
                clip.scroll(to: NSPoint(x: 0, y: 260))
                scrollView.reflectScrolledClipView(clip)
                await pause(0.4)
                print("scrolled to \(Int(clip.bounds.minY))")
                capture("9-scrolled")
                key(.keyDown)
                await pause(0.2)
                key(.keyUp)
                await pause(0.6)
                print("after a hold, scrolled to \(Int(clip.bounds.minY))")
            } else {
                print("no scroll view found")
            }

            // Squash the window as short as it goes.
            let corner = (WidgetLayout.margin + 15) * window.frame.width / WidgetLayout.baseWidth
            await drag(from: NSPoint(x: window.frame.maxX - corner, y: window.frame.minY + corner), by: NSPoint(x: 0, y: 900))
            report("after dragging the grip up as far as it goes")
            capture("10-short")
            NSApp.terminate(nil)
        }
    }

    private static func writeMenuBarIcon(to url: URL) {
        let icon = MascotSprite.menuBarImage()
        let side = 144
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .none
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        _ = write(bitmap, to: url)
    }

    private static func write(_ bitmap: NSBitmapImageRep, to url: URL) -> Bool {
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: url)
            return true
        } catch {
            NSLog("CubeHub: could not write %@: %@", url.path, String(describing: error))
            return false
        }
    }
}
