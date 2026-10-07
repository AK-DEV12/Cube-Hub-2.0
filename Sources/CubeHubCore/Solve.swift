import Foundation

public enum Puzzle: String, Codable, CaseIterable, Sendable {
    case two = "2x2"
    case three = "3x3"
    case four = "4x4"

    /// Stickers along one edge.
    public var size: Int {
        switch self {
        case .two: 2
        case .three: 3
        case .four: 4
        }
    }

    public var scrambleLength: Int {
        switch self {
        case .two: 10
        case .three: 20
        case .four: 40
        }
    }
}

public struct Solve: Codable, Identifiable, Equatable {
    public let id: UUID
    /// Solve time in hundredths of a second.
    public var centis: Int
    public var scramble: String
    public var puzzle: Puzzle
    public var date: Date

    public init(id: UUID = UUID(), centis: Int, scramble: String, puzzle: Puzzle = .three, date: Date = Date()) {
        self.id = id
        self.centis = centis
        self.scramble = scramble
        self.puzzle = puzzle
        self.date = date
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        centis = try container.decode(Int.self, forKey: .centis)
        scramble = try container.decode(String.self, forKey: .scramble)
        // Solves saved before other puzzles existed were all 3x3.
        puzzle = try container.decodeIfPresent(Puzzle.self, forKey: .puzzle) ?? .three
        date = try container.decode(Date.self, forKey: .date)
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
