import Foundation
import Observation
import CubeHubCore

enum MascotMood: Equatable {
    case idle, nervous, ready, solving, solved, celebrating, scrambling
}

/// A solve as the list shows it: numbered within its puzzle, with the running average.
struct SolveEntry: Identifiable {
    let number: Int
    let solve: Solve
    let ao5: Int?
    let isBest: Bool

    var id: Solve.ID { solve.id }
}

@MainActor
@Observable
final class TimerModel {
    enum Phase {
        case idle, holding, ready, running
    }

    /// A panel shown over the card. While one is up, the space bar doesn't start the timer.
    enum Sheet: Equatable {
        case calendar
        case solve(Solve.ID)
    }

    /// How long space has to be held before releasing it starts the timer.
    static let holdDelay: TimeInterval = 0.3
    private static let alwaysOnTopKey = "alwaysOnTop"
    private static let puzzleKey = "puzzle"

    private(set) var phase: Phase = .idle
    private(set) var puzzle: Puzzle
    private(set) var scramble: String
    /// The current puzzle's solves, oldest first.
    private(set) var solves: [Solve] = []
    private(set) var summary = Stats.Summary()
    /// Every solve of the current puzzle, oldest first.
    private(set) var entries: [SolveEntry] = []
    /// How many solves of the current puzzle were done on each day.
    private(set) var solveDays: [Date: Int] = [:]
    /// When set, the list shows only this day's solves. Always the start of a day.
    private(set) var dateFilter: Date?
    private(set) var sheet: Sheet?
    /// The finished time on display while idle; nil shows 0.00.
    private(set) var shownCentis: Int?
    private(set) var mood: MascotMood = .idle
    private(set) var announcement: String?
    private(set) var isFocused = true

    var alwaysOnTop: Bool {
        didSet {
            onAlwaysOnTopChange?(alwaysOnTop)
            guard persistsPreferences else { return }
            UserDefaults.standard.set(alwaysOnTop, forKey: Self.alwaysOnTopKey)
        }
    }

    @ObservationIgnored var onAlwaysOnTopChange: ((Bool) -> Void)?

    @ObservationIgnored private let store: SolveStore
    @ObservationIgnored private let persistsPreferences: Bool
    @ObservationIgnored private let calendar = Calendar.current
    /// Timestamps share NSEvent's clock: seconds since system startup.
    @ObservationIgnored private var startedAt: TimeInterval = 0
    /// The press that stops the timer shouldn't arm the next solve when released.
    @ObservationIgnored private var ignoreNextSpaceUp = false
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    @ObservationIgnored private var moodTask: Task<Void, Never>?

    init(store: SolveStore, persistsPreferences: Bool = true) {
        self.store = store
        self.persistsPreferences = persistsPreferences
        let saved = persistsPreferences ? UserDefaults.standard.string(forKey: Self.puzzleKey).flatMap(Puzzle.init(rawValue:)) : nil
        let puzzle = saved ?? .three
        self.puzzle = puzzle
        self.scramble = Scrambler.generate(for: puzzle)
        self.alwaysOnTop = UserDefaults.standard.object(forKey: Self.alwaysOnTopKey) as? Bool ?? true
        refresh()
    }

    /// The solves in the list, newest first, narrowed to the chosen day if there is one.
    var listedSolves: [SolveEntry] {
        guard let dateFilter else { return entries.reversed() }
        return entries.reversed().filter { calendar.startOfDay(for: $0.solve.date) == dateFilter }
    }

    func entry(for id: Solve.ID) -> SolveEntry? {
        entries.first { $0.id == id }
    }

    func elapsedCentis(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Int {
        TimeFormat.centis(seconds: now - startedAt)
    }

    // MARK: - Keyboard

    func spaceDown(at timestamp: TimeInterval) {
        guard sheet == nil else { return }
        switch phase {
        case .running:
            stop(at: timestamp)
            ignoreNextSpaceUp = true
        case .idle:
            moodTask?.cancel()
            announcement = nil
            phase = .holding
            mood = .nervous
            holdTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.holdDelay))
                guard !Task.isCancelled, let self, self.phase == .holding else { return }
                self.phase = .ready
                self.mood = .ready
            }
        case .holding, .ready:
            break
        }
    }

    func spaceUp(at timestamp: TimeInterval) {
        if ignoreNextSpaceUp {
            ignoreNextSpaceUp = false
            return
        }
        switch phase {
        case .holding:
            // Let go too early.
            holdTask?.cancel()
            phase = .idle
            mood = .idle
        case .ready:
            phase = .running
            startedAt = timestamp
            shownCentis = nil
            mood = .solving
        case .idle, .running:
            break
        }
    }

    /// Closes the open panel, backs out of a hold, or throws away the solve in
    /// progress. Returns false if there was nothing to cancel.
    @discardableResult
    func cancel() -> Bool {
        if sheet != nil {
            sheet = nil
            return true
        }
        switch phase {
        case .idle:
            return false
        case .holding, .ready:
            holdTask?.cancel()
            phase = .idle
            mood = .idle
        case .running:
            phase = .idle
            shownCentis = nil
            announcement = "tossed that one"
            mood = .scrambling
            settleMood(after: 1.4, thenScramble: false)
        }
        return true
    }

    func setFocused(_ focused: Bool) {
        isFocused = focused
        guard !focused else { return }
        // The key-up will never arrive once the window loses focus.
        ignoreNextSpaceUp = false
        if phase == .holding || phase == .ready {
            holdTask?.cancel()
            phase = .idle
            mood = .idle
        }
    }

    // MARK: - Puzzle and scramble

    func selectPuzzle(_ newPuzzle: Puzzle) {
        guard phase == .idle, newPuzzle != puzzle else { return }
        puzzle = newPuzzle
        if persistsPreferences {
            UserDefaults.standard.set(newPuzzle.rawValue, forKey: Self.puzzleKey)
        }
        sheet = nil
        dateFilter = nil
        shownCentis = nil
        refresh()
        newScramble()
    }

    func newScramble() {
        guard phase == .idle else { return }
        scramble = Scrambler.generate(for: puzzle)
        announcement = nil
        mood = .scrambling
        settleMood(after: 0.6, thenScramble: false)
    }

    // MARK: - History

    func showCalendar() {
        guard phase == .idle else { return }
        sheet = .calendar
    }

    func showDetails(for solve: Solve) {
        guard phase == .idle else { return }
        sheet = .solve(solve.id)
    }

    func closeSheet() {
        sheet = nil
    }

    /// Narrows the list to one day, or back to every day with nil.
    func setDateFilter(_ day: Date?) {
        dateFilter = day.map(calendar.startOfDay(for:))
        if sheet == .calendar {
            sheet = nil
        }
    }

    func delete(_ solve: Solve) {
        store.remove(id: solve.id)
        if solves.last?.id == solve.id { shownCentis = nil }
        if sheet == .solve(solve.id) { sheet = nil }
        refresh()
    }

    func deleteLast() {
        guard phase == .idle, let last = solves.last else { return }
        delete(last)
    }

    /// Erases every solve of the current puzzle. Other puzzles keep theirs.
    func clearAll() {
        let puzzle = puzzle
        store.removeAll { $0.puzzle == puzzle }
        shownCentis = nil
        sheet = nil
        refresh()
    }

    // MARK: - Private

    private func stop(at timestamp: TimeInterval) {
        let centis = TimeFormat.centis(seconds: timestamp - startedAt)
        let before = summary
        let solve = Solve(centis: centis, scramble: scramble, puzzle: puzzle)
        store.add(solve)
        // A solve that the day filter would hide shouldn't vanish the moment it's recorded.
        if let dateFilter, calendar.startOfDay(for: solve.date) != dateFilter {
            self.dateFilter = nil
        }
        refresh()

        phase = .idle
        shownCentis = centis
        scramble = Scrambler.generate(for: puzzle)

        var records: [String] = []
        if let old = before.bestSingle, centis < old { records.append("single") }
        if let old = before.bestAo5, let new = summary.bestAo5, new < old { records.append("ao5") }
        if let old = before.bestAo12, let new = summary.bestAo12, new < old { records.append("ao12") }

        if records.isEmpty {
            announcement = nil
            mood = .solved
            settleMood(after: 2.2, thenScramble: true)
        } else {
            announcement = "new best \(records.joined(separator: " + "))!"
            mood = .celebrating
            settleMood(after: 4, thenScramble: true)
        }
    }

    /// Returns the mascot to its resting, scrambled self after a moment.
    private func settleMood(after delay: TimeInterval, thenScramble: Bool) {
        moodTask?.cancel()
        moodTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.phase == .idle else { return }
            self.announcement = nil
            if thenScramble {
                self.mood = .scrambling
                try? await Task.sleep(for: .seconds(0.9))
                guard !Task.isCancelled, self.phase == .idle else { return }
            }
            self.mood = .idle
        }
    }

    private func refresh() {
        solves = store.solves.filter { $0.puzzle == puzzle }
        let times = solves.map(\.centis)
        summary = Stats.summary(times)
        let rollingAo5 = Stats.rollingAverages(times, size: 5)
        entries = solves.enumerated().map { index, solve in
            SolveEntry(number: index + 1, solve: solve, ao5: rollingAo5[index], isBest: solve.centis == summary.bestSingle)
        }
        solveDays = Dictionary(solves.map { (calendar.startOfDay(for: $0.date), 1) }, uniquingKeysWith: +)
        // A day whose last solve was just deleted has nothing left to show.
        if let dateFilter, solveDays[dateFilter] == nil {
            self.dateFilter = nil
        }
    }
}
