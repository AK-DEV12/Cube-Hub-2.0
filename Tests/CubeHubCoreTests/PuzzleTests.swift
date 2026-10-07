import XCTest
@testable import CubeHubCore

/// 2x2 and 4x4. As in CubeTests, expected stickers are worked out by hand with
/// white (up) on top and green (front) facing the solver.
final class BigAndSmallCubeTests: XCTestCase {
    private func rows(_ cube: Cube, _ face: Face, _ rows: [Int]) -> [Face] {
        rows.flatMap { row in (0..<cube.size).map { cube.stickers(on: face)[row * cube.size + $0] } }
    }

    private func columns(_ cube: Cube, _ face: Face, _ columns: [Int]) -> [Face] {
        columns.flatMap { column in (0..<cube.size).map { cube.stickers(on: face)[$0 * cube.size + column] } }
    }

    private func all(_ face: Face, _ count: Int) -> [Face] {
        Array(repeating: face, count: count)
    }

    func testSolvedSizes() {
        XCTAssertEqual(Cube(size: 2).stickers.count, 24)
        XCTAssertEqual(Cube(size: 4).stickers.count, 96)
        XCTAssertEqual(Cube(size: 4).stickers(on: .back), all(.back, 16))
    }

    func testTwoByTwoTurns() {
        let r = Cube(size: 2, scramble: "R")
        XCTAssertEqual(columns(r, .up, [1]), all(.front, 2))
        XCTAssertEqual(columns(r, .front, [1]), all(.down, 2))
        XCTAssertEqual(columns(r, .down, [1]), all(.back, 2))
        XCTAssertEqual(columns(r, .back, [0]), all(.up, 2))
        XCTAssertEqual(columns(r, .up, [0]), all(.up, 2))

        let u = Cube(size: 2, scramble: "U")
        XCTAssertEqual(rows(u, .front, [0]), all(.right, 2))
        XCTAssertEqual(rows(u, .left, [0]), all(.front, 2))
        XCTAssertEqual(rows(u, .front, [1]), all(.front, 2))

        let f = Cube(size: 2, scramble: "F")
        XCTAssertEqual(rows(f, .up, [1]), all(.left, 2))
        XCTAssertEqual(columns(f, .right, [0]), all(.up, 2))
        XCTAssertEqual(rows(f, .down, [0]), all(.right, 2))
        XCTAssertEqual(columns(f, .left, [1]), all(.down, 2))
    }

    func testFourByFourOuterTurnMovesOneLayer() {
        let cube = Cube(size: 4, scramble: "R")
        XCTAssertEqual(columns(cube, .up, [3]), all(.front, 4))
        XCTAssertEqual(columns(cube, .up, [0, 1, 2]), all(.up, 12))
        XCTAssertEqual(columns(cube, .back, [0]), all(.up, 4))
        XCTAssertEqual(columns(cube, .back, [1, 2, 3]), all(.back, 12))
    }

    func testFourByFourWideTurnsMoveTwoLayers() {
        let rw = Cube(size: 4, scramble: "Rw")
        XCTAssertEqual(columns(rw, .up, [2, 3]), all(.front, 8))
        XCTAssertEqual(columns(rw, .up, [0, 1]), all(.up, 8))
        XCTAssertEqual(columns(rw, .front, [2, 3]), all(.down, 8))
        XCTAssertEqual(columns(rw, .down, [2, 3]), all(.back, 8))
        XCTAssertEqual(columns(rw, .back, [0, 1]), all(.up, 8))
        XCTAssertEqual(rw.stickers(on: .right), all(.right, 16))
        XCTAssertEqual(rw.stickers(on: .left), all(.left, 16))

        let uw = Cube(size: 4, scramble: "Uw")
        XCTAssertEqual(rows(uw, .front, [0, 1]), all(.right, 8))
        XCTAssertEqual(rows(uw, .left, [0, 1]), all(.front, 8))
        XCTAssertEqual(rows(uw, .back, [0, 1]), all(.left, 8))
        XCTAssertEqual(rows(uw, .right, [0, 1]), all(.back, 8))
        XCTAssertEqual(rows(uw, .front, [2, 3]), all(.front, 8))

        let fw = Cube(size: 4, scramble: "Fw")
        XCTAssertEqual(rows(fw, .up, [2, 3]), all(.left, 8))
        XCTAssertEqual(columns(fw, .right, [0, 1]), all(.up, 8))
        XCTAssertEqual(rows(fw, .down, [0, 1]), all(.right, 8))
        XCTAssertEqual(columns(fw, .left, [2, 3]), all(.down, 8))
    }

    func testWideTurnsNeedABigCube() {
        var three = Cube(size: 3)
        XCTAssertFalse(three.turn("Rw"))
        XCTAssertEqual(three, Cube(size: 3))
        var two = Cube(size: 2)
        XCTAssertFalse(two.turn("Uw"))
        var four = Cube(size: 4)
        XCTAssertTrue(four.turn("Fw2"))
        XCTAssertEqual(four, Cube(size: 4, scramble: "Fw Fw"))
    }

    func testIdentities() {
        for size in [2, 4] {
            let solved = Cube(size: size)
            let turns = size == 4 ? ["U", "D", "L", "R", "F", "B", "Uw", "Rw", "Fw"] : ["U", "D", "L", "R", "F", "B"]
            for turn in turns {
                XCTAssertEqual(Cube(size: size, scramble: Array(repeating: turn, count: 4).joined(separator: " ")), solved, "\(turn) four times on \(size)x\(size)")
                XCTAssertNotEqual(Cube(size: size, scramble: turn), solved)
                XCTAssertEqual(Cube(size: size, scramble: "\(turn) \(turn)'"), solved)
            }
            XCTAssertEqual(Cube(size: size, scramble: Array(repeating: "R U R' U'", count: 6).joined(separator: " ")), solved)
        }
    }

    func testScrambleThenInverseIsSolved() {
        for puzzle in Puzzle.allCases {
            for _ in 0..<100 {
                let scramble = Scrambler.generate(for: puzzle)
                let inverse = scramble.split(separator: " ").reversed().map { move -> String in
                    if move.hasSuffix("2") { return String(move) }
                    if move.hasSuffix("'") { return String(move.dropLast()) }
                    return move + "'"
                }
                var cube = Cube(size: puzzle.size)
                for move in scramble.split(separator: " ") {
                    XCTAssertTrue(cube.turn(String(move)), "\(move) isn't a \(puzzle.rawValue) move")
                }
                XCTAssertNotEqual(cube, Cube(size: puzzle.size))
                for face in Face.allCases {
                    XCTAssertEqual(cube.stickers.filter { $0 == face }.count, puzzle.size * puzzle.size)
                }
                cube.apply(inverse.joined(separator: " "))
                XCTAssertEqual(cube, Cube(size: puzzle.size))
            }
        }
    }
}

final class PuzzleScrambleTests: XCTestCase {
    private let axis: [String: Int] = [
        "U": 0, "D": 0, "Uw": 0, "L": 1, "R": 1, "Rw": 1, "F": 2, "B": 2, "Fw": 2,
    ]

    private func base(_ move: Substring) -> String {
        String(move).trimmingCharacters(in: CharacterSet(charactersIn: "'2"))
    }

    func testTwoByTwoScrambles() {
        for _ in 0..<500 {
            let moves = Scrambler.generate(for: .two).split(separator: " ")
            XCTAssertEqual(moves.count, 10)
            let bases = moves.map(base)
            XCTAssertTrue(Set(bases).isSubset(of: ["R", "U", "F"]))
            for i in 1..<bases.count {
                XCTAssertNotEqual(bases[i], bases[i - 1])
            }
        }
    }

    func testFourByFourScrambles() {
        var sawWide = false
        for _ in 0..<500 {
            let moves = Scrambler.generate(for: .four).split(separator: " ")
            XCTAssertEqual(moves.count, 40)
            let bases = moves.map(base)
            sawWide = sawWide || bases.contains { $0.hasSuffix("w") }
            // Within an unbroken run on one axis, no turn appears twice.
            var run: [String] = []
            for move in bases {
                let moveAxis = try! XCTUnwrap(axis[move], "unknown move \(move)")
                if let last = run.last, axis[last] == moveAxis {
                    XCTAssertFalse(run.contains(move), "\(move) repeats within \(run)")
                    run.append(move)
                } else {
                    run = [move]
                }
            }
        }
        XCTAssertTrue(sawWide)
    }
}

final class PuzzleStorageTests: XCTestCase {
    func testSolvesSavedBeforePuzzlesExistedAreThreeByThree() throws {
        let json = """
        [{"centis": 2871, "date": "2026-10-06T22:01:12Z", "id": "8F0E2B7A-4C1D-4E55-9A0B-2D3C4E5F6A7B", "scramble": "R U R' U'"}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let solves = try decoder.decode([Solve].self, from: Data(json.utf8))
        XCTAssertEqual(solves.count, 1)
        XCTAssertEqual(solves[0].puzzle, .three)
        XCTAssertEqual(solves[0].centis, 2871)
    }

    func testPuzzleSurvivesReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cubehub-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("solves.json")

        let store = SolveStore(url: url)
        store.add(Solve(centis: 412, scramble: "R U F", puzzle: .two))
        store.add(Solve(centis: 1830, scramble: "R U R'"))
        store.add(Solve(centis: 6500, scramble: "Rw Uw Fw", puzzle: .four))
        XCTAssertEqual(SolveStore(url: url).solves.map(\.puzzle), [.two, .three, .four])

        store.removeAll { $0.puzzle == .three }
        XCTAssertEqual(SolveStore(url: url).solves.map(\.puzzle), [.two, .four])
    }
}
