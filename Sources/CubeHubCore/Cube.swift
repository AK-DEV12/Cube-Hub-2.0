import Foundation

public enum Face: Int, CaseIterable, Sendable {
    case up, down, left, right, front, back
}

/// A cube of any size from 2x2 to 5x5, as stickers each remembered by the face
/// they belong to when solved.
///
/// Stickers are laid out the way an unfolded cube is drawn — U above F, with
/// L, F, R, B in a strip and D below F — and read row by row within each face.
public struct Cube: Equatable {
    public static let sizes = 2...5

    public let size: Int
    public private(set) var stickers: [Face]

    public init(size: Int = 3) {
        precondition(Self.sizes.contains(size), "unsupported cube size \(size)")
        self.size = size
        stickers = Face.allCases.flatMap { Array(repeating: $0, count: size * size) }
    }

    public init(size: Int = 3, scramble: String) {
        self.init(size: size)
        apply(scramble)
    }

    /// The stickers showing on a face, row by row.
    public func stickers(on face: Face) -> [Face] {
        let count = size * size
        return Array(stickers[(face.rawValue * count)..<((face.rawValue + 1) * count)])
    }

    /// Applies moves in WCA notation ("R U2 F'", or "Rw Uw2" on big cubes).
    /// Anything unrecognised is skipped.
    public mutating func apply(_ moves: String) {
        for move in moves.split(whereSeparator: \.isWhitespace) {
            turn(String(move))
        }
    }

    @discardableResult
    public mutating func turn(_ move: String) -> Bool {
        guard let letter = move.first, let face = Self.letters[letter] else { return false }
        var rest = move.dropFirst()
        // "w" turns the outer two layers together.
        var depth = 1
        if rest.first == "w" {
            depth = 2
            rest = rest.dropFirst()
        }
        guard depth <= Self.deepestTurn(size: size) else { return false }
        let quarterTurns: Int
        switch rest {
        case "": quarterTurns = 1
        case "2": quarterTurns = 2
        case "'": quarterTurns = 3
        default: return false
        }
        let sources = Self.tables[size]![face.rawValue][depth - 1]
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

    /// Layers deeper than half the cube are the opposite face's turn.
    private static func deepestTurn(size: Int) -> Int {
        max(1, size / 2)
    }

    /// Where a sticker sits: its cubie's position and the direction it faces.
    /// x points right, y up, z towards the solver. Positions run from -(size - 1)
    /// to size - 1 in steps of two, so even cubes stay on whole numbers.
    private struct Spot: Hashable {
        var x, y, z: Int
        var nx, ny, nz: Int
    }

    private static func spot(_ face: Face, row: Int, column: Int, size: Int) -> Spot {
        let edge = size - 1
        let r = 2 * row - edge
        let c = 2 * column - edge
        switch face {
        case .up: return Spot(x: c, y: edge, z: r, nx: 0, ny: 1, nz: 0)
        case .down: return Spot(x: c, y: -edge, z: -r, nx: 0, ny: -1, nz: 0)
        case .front: return Spot(x: c, y: -r, z: edge, nx: 0, ny: 0, nz: 1)
        case .back: return Spot(x: -c, y: -r, z: -edge, nx: 0, ny: 0, nz: -1)
        case .right: return Spot(x: edge, y: -r, z: -c, nx: 1, ny: 0, nz: 0)
        case .left: return Spot(x: -edge, y: -r, z: c, nx: -1, ny: 0, nz: 0)
        }
    }

    /// A quarter turn of the outer `depth` layers, clockwise as seen looking at
    /// `face`, or nil if the sticker isn't on those layers.
    private static func turned(_ spot: Spot, clockwiseOn face: Face, depth: Int, size: Int) -> Spot? {
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
        let innermost = (size - 1) - 2 * (depth - 1)
        let onLayers: Bool
        switch face {
        case .up: onLayers = spot.y >= innermost
        case .down: onLayers = spot.y <= -innermost
        case .right: onLayers = spot.x >= innermost
        case .left: onLayers = spot.x <= -innermost
        case .front: onLayers = spot.z >= innermost
        case .back: onLayers = spot.z <= -innermost
        }
        guard onLayers else { return nil }
        let position = rotate(spot.x, spot.y, spot.z)
        let normal = rotate(spot.nx, spot.ny, spot.nz)
        return Spot(x: position.0, y: position.1, z: position.2, nx: normal.0, ny: normal.1, nz: normal.2)
    }

    /// For each cube size, face and depth: the slot every sticker comes from
    /// when those layers turn clockwise.
    private static let tables: [Int: [[[Int]]]] = Dictionary(uniqueKeysWithValues: sizes.map { size in
        var spots: [Spot] = []
        for face in Face.allCases {
            for row in 0..<size {
                for column in 0..<size {
                    spots.append(spot(face, row: row, column: column, size: size))
                }
            }
        }
        let slot = Dictionary(uniqueKeysWithValues: spots.enumerated().map { ($1, $0) })
        let faces = Face.allCases.map { face in
            (1...deepestTurn(size: size)).map { depth in
                var sources = Array(spots.indices)
                for (from, spot) in spots.enumerated() {
                    if let destination = turned(spot, clockwiseOn: face, depth: depth, size: size) {
                        sources[slot[destination]!] = from
                    }
                }
                return sources
            }
        }
        return (size, faces)
    })
}
