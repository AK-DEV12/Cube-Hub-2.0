import XCTest
@testable import CubeHubCore

/// Expected stickers are worked out by hand from how a real cube moves, with
/// white (up) on top and green (front) facing the solver.
final class CubeTests: XCTestCase {
    private func row(_ cube: Cube, _ face: Face, _ row: Int) -> [Face] {
        Array(cube.stickers(on: face)[(row * 3)..<(row * 3 + 3)])
    }

    private func column(_ cube: Cube, _ face: Face, _ column: Int) -> [Face] {
        (0..<3).map { cube.stickers(on: face)[$0 * 3 + column] }
    }

    private func all(_ face: Face) -> [Face] {
        Array(repeating: face, count: 3)
    }

    func testSolvedCube() {
        let cube = Cube()
        for face in Face.allCases {
            XCTAssertEqual(cube.stickers(on: face), Array(repeating: face, count: 9))
        }
    }

    func testR() {
        // The right column travels front -> up -> back -> down.
        let cube = Cube(scramble: "R")
        XCTAssertEqual(column(cube, .up, 2), all(.front))
        XCTAssertEqual(column(cube, .front, 2), all(.down))
        XCTAssertEqual(column(cube, .down, 2), all(.back))
        XCTAssertEqual(column(cube, .back, 0), all(.up))
        XCTAssertEqual(column(cube, .up, 0), all(.up))
        XCTAssertEqual(column(cube, .back, 2), all(.back))
        XCTAssertEqual(cube.stickers(on: .right), Array(repeating: .right, count: 9))
        XCTAssertEqual(cube.stickers(on: .left), Array(repeating: .left, count: 9))
    }

    func testL() {
        // The left column travels up -> front -> down -> back.
        let cube = Cube(scramble: "L")
        XCTAssertEqual(column(cube, .front, 0), all(.up))
        XCTAssertEqual(column(cube, .down, 0), all(.front))
        XCTAssertEqual(column(cube, .back, 2), all(.down))
        XCTAssertEqual(column(cube, .up, 0), all(.back))
    }

    func testU() {
        // The top layer travels front -> left -> back -> right.
        let cube = Cube(scramble: "U")
        XCTAssertEqual(row(cube, .front, 0), all(.right))
        XCTAssertEqual(row(cube, .left, 0), all(.front))
        XCTAssertEqual(row(cube, .back, 0), all(.left))
        XCTAssertEqual(row(cube, .right, 0), all(.back))
        XCTAssertEqual(row(cube, .front, 1), all(.front))
    }

    func testD() {
        // The bottom layer travels front -> right -> back -> left.
        let cube = Cube(scramble: "D")
        XCTAssertEqual(row(cube, .right, 2), all(.front))
        XCTAssertEqual(row(cube, .back, 2), all(.right))
        XCTAssertEqual(row(cube, .left, 2), all(.back))
        XCTAssertEqual(row(cube, .front, 2), all(.left))
    }

    func testF() {
        // The front layer travels up -> right -> down -> left.
        let cube = Cube(scramble: "F")
        XCTAssertEqual(row(cube, .up, 2), all(.left))
        XCTAssertEqual(column(cube, .right, 0), all(.up))
        XCTAssertEqual(row(cube, .down, 0), all(.right))
        XCTAssertEqual(column(cube, .left, 2), all(.down))
        XCTAssertEqual(row(cube, .up, 0), all(.up))
    }

    func testB() {
        // The back layer travels up -> left -> down -> right.
        let cube = Cube(scramble: "B")
        XCTAssertEqual(row(cube, .up, 0), all(.right))
        XCTAssertEqual(column(cube, .left, 0), all(.up))
        XCTAssertEqual(row(cube, .down, 2), all(.left))
        XCTAssertEqual(column(cube, .right, 2), all(.down))
    }

    func testTwoMovesKeepStickerOrder() {
        // R puts green down the right of the top face; U then swings it to the front edge.
        let cube = Cube(scramble: "R U")
        XCTAssertEqual(row(cube, .up, 0), all(.up))
        XCTAssertEqual(row(cube, .up, 1), all(.up))
        XCTAssertEqual(row(cube, .up, 2), all(.front))
        XCTAssertEqual(row(cube, .front, 0), all(.right))
        XCTAssertEqual(row(cube, .left, 0), [.front, .front, .down])
        XCTAssertEqual(row(cube, .back, 0), all(.left))
        XCTAssertEqual(row(cube, .right, 0), [.up, .back, .back])
    }

    func testCheckerboard() {
        let opposite: [Face: Face] = [.up: .down, .down: .up, .left: .right, .right: .left, .front: .back, .back: .front]
        let cube = Cube(scramble: "U2 D2 F2 B2 L2 R2")
        for face in Face.allCases {
            let own = face
            let other = opposite[face]!
            XCTAssertEqual(cube.stickers(on: face), [own, other, own, other, own, other, own, other, own])
        }
    }

    func testModifiers() {
        XCTAssertEqual(Cube(scramble: "R2"), Cube(scramble: "R R"))
        XCTAssertEqual(Cube(scramble: "R'"), Cube(scramble: "R R R"))
        XCTAssertEqual(Cube(scramble: "F F'"), Cube())
    }

    func testIdentities() {
        for face in ["U", "D", "L", "R", "F", "B"] {
            XCTAssertEqual(Cube(scramble: "\(face) \(face) \(face) \(face)"), Cube(), "\(face) four times")
            XCTAssertNotEqual(Cube(scramble: face), Cube())
        }
        XCTAssertEqual(Cube(scramble: Array(repeating: "R U R' U'", count: 6).joined(separator: " ")), Cube())
        XCTAssertNotEqual(Cube(scramble: Array(repeating: "R U R' U'", count: 3).joined(separator: " ")), Cube())
    }

    func testScrambleThenInverseIsSolved() {
        for _ in 0..<200 {
            let scramble = Scrambler.generate()
            let inverse = scramble.split(separator: " ").reversed().map { move -> String in
                if move.hasSuffix("2") { return String(move) }
                if move.hasSuffix("'") { return String(move.dropLast()) }
                return move + "'"
            }
            var cube = Cube(scramble: scramble)
            for face in Face.allCases {
                XCTAssertEqual(cube.stickers(on: face)[4], face, "centres never move")
                XCTAssertEqual(cube.stickers.filter { $0 == face }.count, 9)
            }
            cube.apply(inverse.joined(separator: " "))
            XCTAssertEqual(cube, Cube())
        }
    }

    func testUnknownMovesAreSkipped() {
        var cube = Cube()
        XCTAssertFalse(cube.turn("X"))
        XCTAssertFalse(cube.turn("R3"))
        XCTAssertEqual(cube, Cube())
    }
}
