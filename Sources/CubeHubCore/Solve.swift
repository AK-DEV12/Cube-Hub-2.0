import Foundation

public struct Solve: Codable, Identifiable, Equatable {
    public let id: UUID
    /// Solve time in hundredths of a second.
    public var centis: Int
    public var scramble: String
    public var date: Date

    public init(id: UUID = UUID(), centis: Int, scramble: String, date: Date = Date()) {
        self.id = id
        self.centis = centis
        self.scramble = scramble
        self.date = date
    }
}

public enum TimeFormat {
    /// Truncates to hundredths, the way WCA timing does.
    public static func centis(seconds: TimeInterval) -> Int {
        max(0, Int((seconds * 100).rounded(.down)))
    }

    /// "12.34", "1:02.34", "1:00:02.34"
    public static func string(centis: Int) -> String {
        let centis = max(0, centis)
        let hundredths = centis % 100
        let totalSeconds = centis / 100
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, hundredths)
        }
        if minutes > 0 {
            return String(format: "%d:%02d.%02d", minutes, seconds, hundredths)
        }
        return String(format: "%d.%02d", seconds, hundredths)
    }
}
