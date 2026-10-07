import Foundation

public enum Face: Int, CaseIterable, Sendable {
    case up, down, left, right, front, back
}

/// A 3x3 cube as 54 stickers, each remembered by the face it belongs to when solved.
///
/// Stickers are laid out the way an unfolded cube is drawn — U above F, with
/// L, F, R, B in a strip and D below F — and read row by row within each face.
public struct Cube: Equatable {
    public private(set) var stickers: [Face]

    public init() {
        stickers = Face.allCases.flatMap { Array(repeating: $0, count: 9) }
    }

    public init(scramble: String) {
        self.init()
        apply(scramble)
    }

    /// The nine stickers showing on a face, row by row.
    public func stickers(on face: Face) -> [Face] {
        Array(stickers[(face.rawValue * 9)..<(face.rawValue * 9 + 9)])
    }

    /// Applies moves in WCA notation ("R U2 F'"). Anything unrecognised is skipped.
    public mutating func apply(_ moves: String) {
        for move in moves.split(whereSeparator: \.isWhitespace) {
            turn(String(move))
        }
    }

    @discardableResult
    public mutating func turn(_ move: String) -> Bool {
        guard let letter = move.first, let face = Self.letters[letter] else { return false }
        let quarterTurns: Int
        switch move.dropFirst() {
        case "": quarterTurns = 1
        case "2": quarterTurns = 2
        case "'": quarterTurns = 3
        default: return false
        }
        let sources = Self.clockwise[face.rawValue]
        for _ in 0..<quarterTurns {
            let before = stickers
            for slot in stickers.indices {
                stickers[slot] = before[sources[slot]]
            }
        }
        return true
    }

    // MARK: - Geometry

    private static let letters: [Character: Face] = [
        "U": .up, "D": .down, "L": .left, "R": .right, "F": .front, "B": .back,
    ]

    /// Where a sticker sits: its cubie's position and the direction it faces.
    /// x points right, y up, z towards the solver.
    private struct Spot: Hashable {
        var x, y, z: Int
        var nx, ny, nz: Int
    }

    private static func spot(_ face: Face, row: Int, column: Int) -> Spot {
        switch face {
        case .up: Spot(x: column - 1, y: 1, z: row - 1, nx: 0, ny: 1, nz: 0)
        case .down: Spot(x: column - 1, y: -1, z: 1 - row, nx: 0, ny: -1, nz: 0)
        case .front: Spot(x: column - 1, y: 1 - row, z: 1, nx: 0, ny: 0, nz: 1)
        case .back: Spot(x: 1 - column, y: 1 - row, z: -1, nx: 0, ny: 0, nz: -1)
        case .right: Spot(x: 1, y: 1 - row, z: 1 - column, nx: 1, ny: 0, nz: 0)
        case .left: Spot(x: -1, y: 1 - row, z: column - 1, nx: -1, ny: 0, nz: 0)
        }
    }

    /// A quarter turn clockwise as seen looking at `face`, or nil if the sticker isn't on that layer.
    private static func turned(_ spot: Spot, clockwiseOn face: Face) -> Spot? {
        func rotate(_ x: Int, _ y: Int, _ z: Int) -> (Int, Int, Int) {
            switch face {
            case .up: (-z, y, x)
            case .down: (z, y, -x)
            case .right: (x, z, -y)
            case .left: (x, -z, y)
            case .front: (y, -x, z)
            case .back: (-y, x, z)
            }
        }
        let onLayer: Bool
        switch face {
        case .up: onLayer = spot.y == 1
        case .down: onLayer = spot.y == -1
        case .right: onLayer = spot.x == 1
        case .left: onLayer = spot.x == -1
        case .front: onLayer = spot.z == 1
        case .back: onLayer = spot.z == -1
        }
        guard onLayer else { return nil }
        let position = rotate(spot.x, spot.y, spot.z)
        let normal = rotate(spot.nx, spot.ny, spot.nz)
        return Spot(x: position.0, y: position.1, z: position.2, nx: normal.0, ny: normal.1, nz: normal.2)
    }

    /// For each face, the slot every sticker comes from when that face turns clockwise.
    private static let clockwise: [[Int]] = {
        var spots: [Spot] = []
        for face in Face.allCases {
            for row in 0..<3 {
                for column in 0..<3 {
                    spots.append(spot(face, row: row, column: column))
                }
            }
        }
        let slot = Dictionary(uniqueKeysWithValues: spots.enumerated().map { ($1, $0) })
        return Face.allCases.map { face in
            var sources = Array(spots.indices)
            for (from, spot) in spots.enumerated() {
                if let destination = turned(spot, clockwiseOn: face) {
                    sources[slot[destination]!] = from
                }
            }
            return sources
        }
    }()
}
