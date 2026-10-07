import SwiftUI
import CubeHubCore

/// A panel laid over the card, with the card dimmed behind it. Clicking the
/// dimmed area closes it.
struct CardSheet<Content: View>: View {
    let u: CGFloat
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            // Scrolls only when the card is too short to show the whole panel.
            ViewThatFits(in: .vertical) {
                content
                ScrollView {
                    content
                }
                .scrollIndicators(.never)
            }
            .padding(14 * u)
            .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 16 * u, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16 * u, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            // Clicks on the panel itself stay on the panel.
            .contentShape(Rectangle())
            .onTapGesture {}
            .padding(12 * u)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22 * u, style: .continuous))
    }
}

/// A month at a time. Days with solves are lit and can be picked to show only
/// that day in the list.
struct CalendarSheet: View {
    let model: TimerModel
    let u: CGFloat

    @State private var month: Date
    private let calendar = Calendar.current

    init(model: TimerModel, u: CGFloat) {
        self.model = model
        self.u = u
        // Open on the chosen day, or failing that on the most recent solve.
        let anchor = model.dateFilter ?? model.solves.last?.date ?? Date()
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: anchor)?.start ?? anchor)
    }

    private var days: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    /// Empty cells before the 1st so it lands under its weekday.
    private var leadingBlanks: Int {
        (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private var solvesThisMonth: Int {
        days.reduce(0) { $0 + (model.solveDays[$1] ?? 0) }
    }

    var body: some View {
        VStack(spacing: 10 * u) {
            HStack(spacing: 2 * u) {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 14 * u, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
                IconButton(symbol: "chevron.left", help: "Previous month", u: u) { step(-1) }
                IconButton(symbol: "chevron.right", help: "Next month", u: u) { step(1) }
                IconButton(symbol: "xmark", help: "Close", u: u, action: model.closeSheet)
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 2 * u), count: 7)
            LazyVGrid(columns: columns, spacing: 2 * u) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 9 * u, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.faint)
                        .frame(height: 16 * u)
                }
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 32 * u)
                }
                ForEach(days, id: \.self) { day in
                    dayCell(day)
                }
            }

            HStack {
                Text(solvesThisMonth == 1 ? "1 solve this month" : "\(solvesThisMonth) solves this month")
                    .font(.system(size: 10 * u, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                Spacer()
                PillButton(title: "All dates", symbol: nil, tint: Theme.ink, u: u) {
                    model.setDateFilter(nil)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let count = model.solveDays[day] ?? 0
        let isSelected = model.dateFilter == day
        let isToday = calendar.isDateInToday(day)
        return Button {
            model.setDateFilter(day)
        } label: {
            VStack(spacing: 2 * u) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 12 * u, weight: count > 0 ? .bold : .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Theme.card : (count > 0 ? Theme.ink : Theme.faint))
                Circle()
                    .fill(count == 0 ? .clear : (isSelected ? Theme.card : Theme.go))
                    .frame(width: 3.5 * u, height: 3.5 * u)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32 * u)
            .background(isSelected ? Theme.go : (count > 0 ? Theme.inset : .clear), in: RoundedRectangle(cornerRadius: 8 * u, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8 * u, style: .continuous)
                    .strokeBorder(isToday && !isSelected ? Theme.faint : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(count == 0)
        .help(count == 0 ? "No solves" : (count == 1 ? "1 solve" : "\(count) solves"))
    }

    private func step(_ months: Int) {
        if let moved = calendar.date(byAdding: .month, value: months, to: month) {
            month = moved
        }
    }
}

/// Everything about one solve: its time, when it happened, the scramble, and
/// the cube that scramble produces.
struct SolveSheet: View {
    let entry: SolveEntry
    let u: CGFloat
    let onClose: () -> Void
    let onDelete: () -> Void

    private var solve: Solve { entry.solve }

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * u) {
            HStack {
                Text("\(solve.puzzle.rawValue) · SOLVE \(entry.number)")
                    .font(.system(size: 10 * u, weight: .bold, design: .rounded))
                    .tracking(1.2 * u)
                    .foregroundStyle(Theme.muted)
                Spacer()
                IconButton(symbol: "xmark", help: "Close", u: u, action: onClose)
            }

            VStack(alignment: .leading, spacing: 4 * u) {
                HStack(alignment: .firstTextBaseline, spacing: 8 * u) {
                    Text(TimeFormat.string(centis: solve.centis))
                        .font(.system(size: 40 * u, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(entry.isBest ? Theme.go : Theme.ink)
                    if entry.isBest {
                        PBTag(u: u)
                    }
                    Spacer()
                    if let ao5 = entry.ao5 {
                        Text("ao5 \(TimeFormat.string(centis: ao5))")
                            .font(.system(size: 11 * u, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.muted)
                    }
                }
                Text(solve.date.formatted(date: .complete, time: .shortened))
                    .font(.system(size: 11 * u, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
            }

            VStack(alignment: .leading, spacing: 6 * u) {
                Text("SCRAMBLE")
                    .font(.system(size: 9 * u, weight: .bold, design: .rounded))
                    .tracking(1.2 * u)
                    .foregroundStyle(Theme.faint)
                Text(solve.scramble)
                    .font(.system(size: (solve.puzzle == .four ? 11 : 13) * u, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(3 * u)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            CubeNetView(cube: Cube(size: solve.puzzle.size, scramble: solve.scramble), faceSize: 38, u: u)
                .padding(.vertical, 10 * u)
                .frame(maxWidth: .infinity)
                .background(Theme.inset, in: RoundedRectangle(cornerRadius: 12 * u, style: .continuous))
                .help("The scrambled cube, held with white on top and green facing you")

            HStack {
                PillButton(title: "Copy Scramble", symbol: "doc.on.doc", tint: Theme.ink, u: u) {
                    Pasteboard.copy(solve.scramble)
                }
                Spacer()
                PillButton(title: "Delete", symbol: "trash", tint: Theme.hold, u: u, action: onDelete)
            }
        }
    }
}

struct PillButton: View {
    let title: String
    let symbol: String?
    let tint: Color
    let u: CGFloat
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5 * u) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9 * u, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11 * u, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10 * u)
            .frame(height: 24 * u)
            .background(Color.white.opacity(hovering ? 0.12 : 0.07), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
    }
}
