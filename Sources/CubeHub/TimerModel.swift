import Foundation
import Observation
import CubeHubCore

enum MascotMood: Equatable {
    case idle, nervous, ready, solving, solved, celebrating, scrambling
}

@MainActor
@Observable
final class TimerModel {
    enum Phase {
        case idle, holding, ready, running
    }

    /// How long space has to be held before releasing it starts the timer.
    static let holdDelay: TimeInterval = 0.3
    private static let alwaysOnTopKey = "alwaysOnTop"

    private(set) var phase: Phase = .idle
    private(set) var scramble: String
    /// Oldest first.
    private(set) var solves: [Solve] = []
    private(set) var summary = Stats.Summary()
    private(set) var rollingAo5: [Int?] = []
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
    /// Timestamps share NSEvent's clock: seconds since system startup.
    @ObservationIgnored private var startedAt: TimeInterval = 0
    /// The press that stops the timer shouldn't arm the next solve when released.
    @ObservationIgnored private var ignoreNextSpaceUp = false
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    @ObservationIgnored private var moodTask: Task<Void, Never>?

    init(store: SolveStore, persistsPreferences: Bool = true) {
        self.store = store
        self.persistsPreferences = persistsPreferences
        self.scramble = Scrambler.generate()
        self.alwaysOnTop = UserDefaults.standard.object(forKey: Self.alwaysOnTopKey) as? Bool ?? true
        refresh()
    }

    func elapsedCentis(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Int {
        TimeFormat.centis(seconds: now - startedAt)
    }

    // MARK: - Keyboard

    func spaceDown(at timestamp: TimeInterval) {
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

    /// Backs out of a hold, or throws away the solve in progress.
    /// Returns false if there was nothing to cancel.
    @discardableResult
    func cancel() -> Bool {
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
            cancel()
        }
    }

    // MARK: - History

    func newScramble() {
        guard phase == .idle else { return }
        scramble = Scrambler.generate()
        announcement = nil
        mood = .scrambling
        settleMood(after: 0.6, thenScramble: false)
    }

    func delete(_ solve: Solve) {
        store.remove(id: solve.id)
        if solves.last?.id == solve.id { shownCentis = nil }
        refresh()
    }

    func deleteLast() {
        guard phase == .idle, let last = solves.last else { return }
        delete(last)
    }

    func clearAll() {
        store.removeAll()
        shownCentis = nil
        refresh()
    }

    // MARK: - Private

    private func stop(at timestamp: TimeInterval) {
        let centis = TimeFormat.centis(seconds: timestamp - startedAt)
        let before = summary
        store.add(Solve(centis: centis, scramble: scramble))
        refresh()

        phase = .idle
        shownCentis = centis
        scramble = Scrambler.generate()

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
        solves = store.solves
        let times = solves.map(\.centis)
        summary = Stats.summary(times)
        rollingAo5 = Stats.rollingAverages(times, size: 5)
    }
}
