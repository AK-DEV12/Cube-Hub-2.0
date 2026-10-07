import SwiftUI
import CubeHubCore

enum Theme {
    static let card = Color(red: 0.122, green: 0.118, blue: 0.114)
    static let ink = Color(red: 0.96, green: 0.955, blue: 0.93)
    static let muted = Color.white.opacity(0.5)
    static let faint = Color.white.opacity(0.3)
    static let inset = Color.white.opacity(0.055)
    static let stroke = Color.white.opacity(0.13)
    static let go = CubeColor.green.color
    static let hold = CubeColor.red.color
}

/// The widget is designed at `baseWidth` points wide and everything scales with
/// the window's width. The card's contents scroll, so the window can be any
/// height; the card sits flush with the top of the window so it can be parked
/// right under the menu bar.
enum WidgetLayout {
    static let cardWidth: CGFloat = 320
    /// Clear space right of and below the card so its shadow isn't clipped by the window.
    static let margin: CGFloat = 18
    /// Clear space left of the card for Cubby to lean out into.
    static let gutter: CGFloat = 66
    static let baseWidth = gutter + cardWidth + margin
    static let defaultBaseHeight: CGFloat = 530
    /// Short enough to show just the scramble and the timer.
    static let minBaseHeight: CGFloat = 240
    static let maxBaseHeight: CGFloat = 1290
    static let scaleRange: ClosedRange<CGFloat> = 0.8...2.2
    static let defaultScale: CGFloat = 1.2
}

enum DragPhase {
    case changed, ended
}

struct WidgetActions {
    /// Pops up the app menu at the pointer.
    var showMenu: () -> Void = {}
    /// The card is being dragged around the screen.
    var move: (DragPhase) -> Void = { _ in }
    /// The resize grip is being dragged.
    var resize: (DragPhase) -> Void = { _ in }
}

struct WidgetView: View {
    let model: TimerModel
    var actions = WidgetActions()

    var body: some View {
        GeometryReader { geometry in
            WidgetContent(model: model, actions: actions, u: geometry.size.width / WidgetLayout.baseWidth)
        }
    }
}

/// `u` is the length of one design point at the current window size.
private struct WidgetContent: View {
    let model: TimerModel
    let actions: WidgetActions
    let u: CGFloat

    private var isRunning: Bool { model.phase == .running }

    var body: some View {
        let cube = Cube(scramble: model.scramble)
        ZStack(alignment: .topLeading) {
            peekingMascot(cube)
            card(cube)
                .padding(.leading, WidgetLayout.gutter * u)
                .padding([.trailing, .bottom], WidgetLayout.margin * u)
        }
    }

    /// How many of Cubby's twelve pixel columns lean out from behind the card.
    private var peek: CGFloat {
        switch model.mood {
        case .nervous: 3
        case .idle, .solving, .scrambling: 7
        case .ready: 9
        case .solved, .celebrating: 10
        }
    }

    /// Cubby hides behind the card's left edge, wearing the scramble's front face.
    private func peekingMascot(_ cube: Cube) -> some View {
        // Whole half-points keep the sprite's pixels sharp.
        let pixel = max(1, (5 * u * 2).rounded() / 2)
        return MascotView(
            mood: model.mood,
            pattern: cube.stickers(on: .front).map(CubeColor.init(face:)),
            pixel: pixel
        )
        .offset(x: WidgetLayout.gutter * u - (CGFloat(MascotSprite.bodyLeft) + peek) * pixel, y: 20 * u)
        .animation(.spring(duration: 0.4, bounce: 0.35), value: model.mood)
        .allowsHitTesting(false)
    }

    private static let topID = "top"

    /// Everything in the card scrolls as one page.
    private func card(_ cube: Cube) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14 * u) {
                    header
                    scramble
                        .opacity(isRunning ? 0.25 : 1)
                    VStack(spacing: 2 * u) {
                        TimerReadout(model: model, u: u)
                        hint
                    }
                    Group {
                        HStack(spacing: 10 * u) {
                            netPanel(cube)
                            statsPanel
                        }
                        history
                    }
                    .opacity(isRunning ? 0.25 : 1)
                    .allowsHitTesting(!isRunning)
                }
                .padding(16 * u)
                .id(Self.topID)
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            // Content fades out under the card's top and bottom edges.
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 10 * u)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 16 * u)
                }
            )
            .onChange(of: model.phase) { _, phase in
                // Bring the timer back into view as soon as a solve is on its way.
                if phase == .holding {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(Self.topID, anchor: .top)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22 * u, style: .continuous)
                .fill(Theme.card)
                .shadow(color: .black.opacity(0.35), radius: 12 * u, y: 5 * u)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22 * u, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
        // Moved by hand rather than with WindowDragGesture, which lets macOS
        // tile the widget when it's dragged against the top of the screen.
        .modifier(PointerDrag(minimumDistance: 3, onDrag: actions.move))
        .overlay(alignment: .bottomTrailing) {
            ResizeGrip(u: u, onDrag: actions.resize)
        }
        // Dragging works on the first click, even when another app has focus.
        .allowsWindowActivationEvents(true)
        .animation(.easeOut(duration: 0.15), value: isRunning)
    }

    private var header: some View {
        HStack(spacing: 2 * u) {
            Text("CUBE HUB")
                .font(.system(size: 11 * u, weight: .bold, design: .rounded))
                .tracking(1.6 * u)
                .foregroundStyle(Theme.muted)
            Spacer()
            IconButton(symbol: "shuffle", help: "New scramble", u: u) {
                model.newScramble()
            }
            .disabled(model.phase != .idle)
            IconButton(symbol: model.alwaysOnTop ? "pin.fill" : "pin", help: "Keep on top of other windows", u: u) {
                model.alwaysOnTop.toggle()
            }
            IconButton(symbol: "ellipsis", help: "More", u: u, action: actions.showMenu)
                .disabled(isRunning)
        }
    }

    private var scramble: some View {
        Text(model.scramble)
            .font(.system(size: 15 * u, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .lineSpacing(3 * u)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 42 * u)
            .contextMenu {
                Button("Copy Scramble") { copy(model.scramble) }
            }
    }

    /// Under the timer: what to do next, or the news when a record falls.
    private var hint: some View {
        Text(model.announcement ?? hintText)
            .font(.system(size: 11 * u, weight: model.announcement == nil ? .medium : .bold, design: .rounded))
            .foregroundStyle(model.announcement == nil ? Theme.muted : Theme.go)
            .lineLimit(1)
    }

    private var hintText: String {
        if !model.isFocused && model.phase != .running { return "click the widget, then hold space" }
        switch model.phase {
        case .idle: return "hold space, then release to start"
        case .holding: return "keep holding…"
        case .ready: return "release to start"
        case .running: return "space to stop · esc to discard"
        }
    }

    // MARK: - Scramble preview and stats

    private static let panelHeight: CGFloat = 108

    private func netPanel(_ cube: Cube) -> some View {
        CubeNetView(cube: cube, u: u)
            .padding(.horizontal, 9 * u)
            .frame(height: Self.panelHeight * u)
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 12 * u, style: .continuous))
            .help("How the cube looks after this scramble, held with white on top and green facing you")
    }

    private var statsPanel: some View {
        VStack(spacing: 8 * u) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                columnTitle("NOW")
                columnTitle("BEST")
            }
            statsRow("single", now: model.summary.lastSingle, best: model.summary.bestSingle)
            statsRow("ao5", now: model.summary.ao5, best: model.summary.bestAo5)
            statsRow("ao12", now: model.summary.ao12, best: model.summary.bestAo12)
        }
        .padding(.horizontal, 10 * u)
        .frame(maxWidth: .infinity)
        .frame(height: Self.panelHeight * u)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 12 * u, style: .continuous))
    }

    private static let statColumn: CGFloat = 46

    private func columnTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 8 * u, weight: .bold, design: .rounded))
            .tracking(1 * u)
            .foregroundStyle(Theme.faint)
            .frame(width: Self.statColumn * u, alignment: .trailing)
    }

    private func statsRow(_ label: String, now: Int?, best: Int?) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 11 * u, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
            statValue(now, highlighted: now != nil && now == best)
            statValue(best, highlighted: false)
        }
    }

    private func statValue(_ centis: Int?, highlighted: Bool) -> some View {
        Text(centis.map(TimeFormat.string(centis:)) ?? "–")
            .font(.system(size: 13 * u, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(centis == nil ? Theme.faint : (highlighted ? Theme.go : Theme.ink))
            .frame(width: Self.statColumn * u, alignment: .trailing)
    }

    // MARK: - History

    private var history: some View {
        VStack(alignment: .leading, spacing: 6 * u) {
            Text(model.solves.isEmpty ? "SOLVES" : "SOLVES · \(model.solves.count)")
                .font(.system(size: 9 * u, weight: .bold, design: .rounded))
                .tracking(1.2 * u)
                .foregroundStyle(Theme.faint)
                .padding(.leading, 4 * u)
            if model.solves.isEmpty {
                Text("No solves yet.\nYour times will land here.")
                    .font(.system(size: 12 * u, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.faint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(height: 80 * u)
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(Array(model.solves.enumerated().reversed()), id: \.element.id) { index, solve in
                        SolveRow(
                            number: index + 1,
                            solve: solve,
                            ao5: model.rollingAo5[index],
                            isBest: solve.centis == model.summary.bestSingle,
                            u: u,
                            onCopy: { copy(solve.scramble) },
                            onDelete: { model.delete(solve) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// The scrambled cube unfolded: U on top, then L F R B in a strip, D below F.
private struct CubeNetView: View {
    let cube: Cube
    let u: CGFloat

    private static let sticker: CGFloat = 8.5
    private static let stickerGap: CGFloat = 1
    private static let faceGap: CGFloat = 2.5
    private static let faceSize = sticker * 3 + stickerGap * 2
    private static let placement: [(face: Face, column: CGFloat, row: CGFloat)] = [
        (.up, 1, 0), (.left, 0, 1), (.front, 1, 1), (.right, 2, 1), (.back, 3, 1), (.down, 1, 2),
    ]

    var body: some View {
        Canvas { context, _ in
            for (face, faceColumn, faceRow) in Self.placement {
                let stickers = cube.stickers(on: face)
                let originX = faceColumn * (Self.faceSize + Self.faceGap)
                let originY = faceRow * (Self.faceSize + Self.faceGap)
                for index in 0..<9 {
                    let rect = CGRect(
                        x: (originX + CGFloat(index % 3) * (Self.sticker + Self.stickerGap)) * u,
                        y: (originY + CGFloat(index / 3) * (Self.sticker + Self.stickerGap)) * u,
                        width: Self.sticker * u,
                        height: Self.sticker * u
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 1.6 * u),
                        with: .color(CubeColor(face: stickers[index]).color)
                    )
                }
            }
        }
        .frame(
            width: (Self.faceSize * 4 + Self.faceGap * 3) * u,
            height: (Self.faceSize * 3 + Self.faceGap * 2) * u
        )
        .accessibilityLabel("Scrambled cube preview")
    }
}

private struct TimerReadout: View {
    let model: TimerModel
    let u: CGFloat

    var body: some View {
        Group {
            switch model.phase {
            case .running:
                TimelineView(.animation) { _ in
                    digits(model.elapsedCentis())
                }
            case .holding, .ready:
                digits(0)
            case .idle:
                digits(model.shownCentis ?? 0)
            }
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .frame(height: 76 * u)
    }

    private var color: Color {
        switch model.phase {
        case .holding: Theme.hold
        case .ready: Theme.go
        case .idle, .running: Theme.ink
        }
    }

    private func digits(_ centis: Int) -> some View {
        Text(TimeFormat.string(centis: centis))
            .font(.system(size: 68 * u, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

private struct SolveRow: View {
    let number: Int
    let solve: Solve
    let ao5: Int?
    let isBest: Bool
    let u: CGFloat
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8 * u) {
            Text("\(number)")
                .font(.system(size: 11 * u, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.faint)
                .frame(width: 30 * u, alignment: .trailing)
            Text(TimeFormat.string(centis: solve.centis))
                .font(.system(size: 14 * u, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isBest ? Theme.go : Theme.ink)
            if isBest {
                Text("PB")
                    .font(.system(size: 9 * u, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.card)
                    .padding(.horizontal, 5 * u)
                    .padding(.vertical, 2 * u)
                    .background(Theme.go, in: Capsule())
            }
            Spacer()
            if hovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9 * u, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 18 * u, height: 18 * u)
                        .background(Theme.inset, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Delete this solve")
            } else if let ao5 {
                Text("ao5 \(TimeFormat.string(centis: ao5))")
                    .font(.system(size: 11 * u, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 6 * u)
        .frame(height: 26 * u)
        .background(hovering ? Theme.inset : .clear, in: RoundedRectangle(cornerRadius: 7 * u, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copy Scramble", action: onCopy)
            Button("Delete Solve", role: .destructive, action: onDelete)
        }
        .help(solve.scramble)
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    let u: CGFloat
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12 * u, weight: .semibold))
                .foregroundStyle(isEnabled ? Theme.muted : Theme.faint)
                .frame(width: 26 * u, height: 26 * u)
                .background(hovering && isEnabled ? Theme.inset : .clear, in: RoundedRectangle(cornerRadius: 7 * u, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Reports a click-and-drag, including when the drag is cut short.
private struct PointerDrag: ViewModifier {
    let minimumDistance: CGFloat
    let onDrag: (DragPhase) -> Void

    @GestureState private var isDragging = false

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: minimumDistance)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { _ in onDrag(.changed) }
            )
            .onChange(of: isDragging) { _, dragging in
                if !dragging { onDrag(.ended) }
            }
    }
}

/// Drag the card's bottom corner: wider makes everything bigger, taller shows more at once.
private struct ResizeGrip: View {
    let u: CGFloat
    let onDrag: (DragPhase) -> Void

    @State private var hovering = false

    var body: some View {
        Canvas { context, size in
            var lines = Path()
            for inset in [5.0, 9.0] {
                lines.move(to: CGPoint(x: size.width - inset * u, y: size.height - 4 * u))
                lines.addLine(to: CGPoint(x: size.width - 4 * u, y: size.height - inset * u))
            }
            context.stroke(lines, with: .color(hovering ? Theme.muted : Theme.faint), style: StrokeStyle(lineWidth: 1.4 * u, lineCap: .round))
        }
        .frame(width: 22 * u, height: 22 * u)
        .padding([.trailing, .bottom], 4 * u)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .pointerStyle(.frameResize(position: .bottomTrailing))
        .modifier(PointerDrag(minimumDistance: 0, onDrag: onDrag))
        .help("Drag to resize")
    }
}
