import Foundation

/// Random-move scrambles in WCA notation.
public enum Scrambler {
    private struct Turn {
        let name: String
        let axis: Int
    }

    private static let suffixes = ["", "'", "2"]

    private static func turns(for puzzle: Puzzle) -> [Turn] {
        let outer = [
            Turn(name: "U", axis: 0), Turn(name: "D", axis: 0),
            Turn(name: "L", axis: 1), Turn(name: "R", axis: 1),
            Turn(name: "F", axis: 2), Turn(name: "B", axis: 2),
        ]
        switch puzzle {
        case .two:
            // Three faces reach every 2x2 position; the rest would only turn the whole cube.
            return [Turn(name: "R", axis: 1), Turn(name: "U", axis: 0), Turn(name: "F", axis: 2)]
        case .three:
            return outer
        case .four:
            return outer + [Turn(name: "Uw", axis: 0), Turn(name: "Rw", axis: 1), Turn(name: "Fw", axis: 2)]
        }
    }

    public static func generate<G: RandomNumberGenerator>(for puzzle: Puzzle = .three, length: Int? = nil, using rng: inout G) -> String {
        let turns = turns(for: puzzle)
        let length = length ?? puzzle.scrambleLength
        var moves: [String] = []
        // Turns on one axis commute, so repeating one within an unbroken run
        // on that axis ("R L R") would just be a longer way to write a shorter scramble.
        var runAxis: Int?
        var run: [Int] = []
        while moves.count < length {
            let pick = Int.random(in: turns.indices, using: &rng)
            if turns[pick].axis == runAxis {
                if run.contains(pick) { continue }
                run.append(pick)
            } else {
                runAxis = turns[pick].axis
                run = [pick]
            }
            moves.append(turns[pick].name + suffixes.randomElement(using: &rng)!)
        }
        return moves.joined(separator: " ")
    }

    public static func generate(for puzzle: Puzzle = .three, length: Int? = nil) -> String {
        var rng = SystemRandomNumberGenerator()
        return generate(for: puzzle, length: length, using: &rng)
    }
}
