import Foundation

/// Random-move 3x3 scrambles in WCA notation.
public enum Scrambler {
    private static let faces: [(name: String, axis: Int)] = [
        ("U", 0), ("D", 0), ("L", 1), ("R", 1), ("F", 2), ("B", 2),
    ]
    private static let suffixes = ["", "'", "2"]

    public static func generate<G: RandomNumberGenerator>(length: Int = 20, using rng: inout G) -> String {
        var moves: [String] = []
        var last: Int?
        var beforeLast: Int?
        while moves.count < length {
            let face = Int.random(in: 0..<faces.count, using: &rng)
            // Never turn the same face twice in a row.
            if face == last { continue }
            // Opposite faces commute, so "R L R" is really "R2 L" — skip it.
            if let last, let beforeLast,
               faces[face].axis == faces[last].axis,
               faces[beforeLast].axis == faces[last].axis {
                continue
            }
            moves.append(faces[face].name + suffixes.randomElement(using: &rng)!)
            beforeLast = last
            last = face
        }
        return moves.joined(separator: " ")
    }

    public static func generate(length: Int = 20) -> String {
        var rng = SystemRandomNumberGenerator()
        return generate(length: length, using: &rng)
    }
}
