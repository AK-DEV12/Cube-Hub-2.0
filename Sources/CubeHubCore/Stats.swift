import Foundation

/// Averages over solve times, all in hundredths of a second, oldest solve first.
public enum Stats {
    public struct Summary: Equatable {
        public var count = 0
        public var lastSingle: Int?
        public var bestSingle: Int?
        public var ao5: Int?
        public var bestAo5: Int?
        public var ao12: Int?
        public var bestAo12: Int?

        public init() {}
    }

    /// WCA-style average: drop the fastest and the slowest time, take the mean
    /// of the rest, rounded to the nearest hundredth.
    public static func trimmedAverage<C: Collection>(_ times: C) -> Int? where C.Element == Int {
        guard times.count >= 3 else { return nil }
        var sum = 0
        var fastest = Int.max
        var slowest = Int.min
        for time in times {
            sum += time
            fastest = min(fastest, time)
            slowest = max(slowest, time)
        }
        let kept = times.count - 2
        return (2 * (sum - fastest - slowest) + kept) / (2 * kept)
    }

    /// The average of the `size` solves ending at each index, or nil where
    /// there aren't enough solves yet.
    public static func rollingAverages(_ times: [Int], size: Int) -> [Int?] {
        times.indices.map { end in
            end + 1 >= size ? trimmedAverage(times[(end + 1 - size)...end]) : nil
        }
    }

    public static func summary(_ times: [Int]) -> Summary {
        var summary = Summary()
        summary.count = times.count
        summary.lastSingle = times.last
        summary.bestSingle = times.min()

        let ao5 = rollingAverages(times, size: 5)
        summary.ao5 = ao5.last ?? nil
        summary.bestAo5 = ao5.compactMap { $0 }.min()

        let ao12 = rollingAverages(times, size: 12)
        summary.ao12 = ao12.last ?? nil
        summary.bestAo12 = ao12.compactMap { $0 }.min()
        return summary
    }
}
