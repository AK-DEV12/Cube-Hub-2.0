import SwiftUI
import CubeHubCore

enum Theme {
    static let card = Color(red: 0.122, green: 0.118, blue: 0.114)
    static let sheet = Color(red: 0.165, green: 0.16, blue: 0.155)
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
        let cube = Cube(size: model.puzzle.size, scramble: model.scramble)
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
        return MascotView(mood: model.mood, pattern: MascotSprite.pattern(for: cube), pixel: pixel)
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
        .overlay {
            if let sheet = model.sheet {
                CardSheet(u: u, onDismiss: model.closeSheet) {
                    switch sheet {
                    case .calendar:
                        CalendarSheet(model: model, u: u)
                    case .solve(let id):
                        if let entry = model.entry(for: id) {
                            SolveSheet(entry: entry, u: u, onClose: model.closeSheet) {
                                model.delete(entry.solve)
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        // Dragging works on the first click, even when another app has focus.
        .allowsWindowActivationEvents(true)
        .animation(.easeOut(duration: 0.15), value: isRunning)
        .animation(.easeOut(duration: 0.15), value: model.sheet)
    }

    private var header: some View {
        HStack(spacing: 2 * u) {
            PuzzlePicker(selection: model.puzzle, u: u, onSelect: model.selectPuzzle)
                .disabled(model.phase != .idle)
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

    /// Longer scrambles are set smaller so they stay a few lines tall.
    private var scrambleFontSize: CGFloat {
        switch model.puzzle {
        case .two: 17
        case .three: 15
        case .four: 12
        }
    }

    private var scramble: some View {
        Text(model.scramble)
            .font(.system(size: scrambleFontSize * u, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .lineSpacing(3 * u)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 42 * u)
            .contextMenu {
                Button("Copy Scramble") { Pasteboard.copy(model.scramble) }
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
        CubeNetView(cube: cube, faceSize: 27.5, u: u)
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
        .padding(.horizontal, 8 * u)
        .frame(maxWidth: .infinity)
        .frame(height: Self.panelHeight * u)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 12 * u, style: .continuous))
    }

    private static let statColumn: CGFloat = 47

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
            // A little narrower than its column, so minute-long times don't run into each other.
            .frame(width: (Self.statColumn - 6) * u, alignment: .trailing)
            .frame(width: Self.statColumn * u, alignment: .trailing)
    }

    // MARK: - History

    private var history: some View {
        let listed = model.listedSolves
        return VStack(alignment: .leading, spacing: 6 * u) {
            HStack(spacing: 4 * u) {
                Text(listed.isEmpty ? "SOLVES" : "SOLVES · \(listed.count)")
                    .font(.system(size: 9 * u, weight: .bold, design: .rounded))
                    .tracking(1.2 * u)
                    .foregroundStyle(Theme.faint)
                    .padding(.leading, 4 * u)
                Spacer()
                DateFilterButton(day: model.dateFilter, u: u, onOpen: model.showCalendar) {
                    model.setDateFilter(nil)
                }
                .disabled(model.solves.isEmpty)
            }
            if listed.isEmpty {
                Text("No \(model.puzzle.rawValue) solves yet.\nYour times will land here.")
                    .font(.system(size: 12 * u, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.faint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(height: 80 * u)
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(listed) { entry in
                        SolveRow(
                            entry: entry,
                            u: u,
                            onInfo: { model.showDetails(for: entry.solve) },
                            onDelete: { model.delete(entry.solve) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum Pasteboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Chooses which puzzle is being timed. Each keeps its own solves and averages.
private struct PuzzlePicker: View {
    let selection: Puzzle
    let u: CGFloat
    let onSelect: (Puzzle) -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 2 * u) {
            ForEach(Puzzle.allCases, id: \.self) { puzzle in
                Button {
                    onSelect(puzzle)
                } label: {
                    Text(puzzle.rawValue)
                        .font(.system(size: 11 * u, weight: .bold, design: .rounded))
                        .foregroundStyle(puzzle == selection ? Theme.ink : (isEnabled ? Theme.muted : Theme.faint))
                        .frame(width: 36 * u, height: 22 * u)
                        .background(puzzle == selection ? Color.white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6 * u, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Time \(puzzle.rawValue) solves")
            }
        }
        .padding(2 * u)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 8 * u, style: .continuous))
    }
}

/// Opens the calendar; once a day is chosen it names the day and offers a way back.
private struct DateFilterButton: View {
    let day: Date?
    let u: CGFloat
    let onOpen: () -> Void
    let onClear: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 2 * u) {
            Button(action: onOpen) {
                HStack(spacing: 4 * u) {
                    Image(systemName: "calendar")
                        .font(.system(size: 9 * u, weight: .semibold))
                    Text(day.map(DayFormat.short) ?? "All dates")
                        .font(.system(size: 10 * u, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(day == nil ? (isEnabled ? Theme.muted : Theme.faint) : Theme.card)
                .padding(.horizontal, 7 * u)
                .frame(height: 20 * u)
                .background(day == nil ? Theme.inset : Theme.go, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Show solves from one day")
            if day != nil {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8 * u, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 20 * u, height: 20 * u)
                        .background(Theme.inset, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Show every day")
            }
        }
    }
}

enum DayFormat {
    /// "Oct 6", with the year added once it isn't this one.
    static func short(_ day: Date) -> String {
        let sameYear = Calendar.current.isDate(day, equalTo: Date(), toGranularity: .year)
        return day.formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
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
    let entry: SolveEntry
    let u: CGFloat
    let onInfo: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8 * u) {
            Text("\(entry.number)")
                .font(.system(size: 11 * u, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.faint)
                .frame(width: 30 * u, alignment: .trailing)
            Text(TimeFormat.string(centis: entry.solve.centis))
                .font(.system(size: 14 * u, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(entry.isBest ? Theme.go : Theme.ink)
            if entry.isBest {
                PBTag(u: u)
            }
            Spacer()
            if hovering {
                rowButton("xmark", help: "Delete this solve", action: onDelete)
            } else if let ao5 = entry.ao5 {
                Text("ao5 \(TimeFormat.string(centis: ao5))")
                    .font(.system(size: 11 * u, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
            rowButton("info", help: "More info", action: onInfo)
        }
        .padding(.horizontal, 6 * u)
        .frame(height: 26 * u)
        .background(hovering ? Theme.inset : .clear, in: RoundedRectangle(cornerRadius: 7 * u, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("More Info", action: onInfo)
            Button("Copy Scramble") { Pasteboard.copy(entry.solve.scramble) }
            Button("Delete Solve", role: .destructive, action: onDelete)
        }
    }

    private func rowButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9 * u, weight: .bold))
                .foregroundStyle(hovering ? Theme.ink : Theme.muted)
                .frame(width: 18 * u, height: 18 * u)
                .background(Theme.inset, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }
}

struct PBTag: View {
    let u: CGFloat

    var body: some View {
        Text("PB")
            .font(.system(size: 9 * u, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.card)
            .padding(.horizontal, 5 * u)
            .padding(.vertical, 2 * u)
            .background(Theme.go, in: Capsule())
    }
}

struct IconButton: View {
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
