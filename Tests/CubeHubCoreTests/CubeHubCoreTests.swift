import XCTest
@testable import CubeHubCore

final class StatsTests: XCTestCase {
    func testTrimmedAverageDropsBestAndWorst() {
        XCTAssertEqual(Stats.trimmedAverage([1000, 1200, 1100, 5000, 900]), 1100)
        XCTAssertEqual(Stats.trimmedAverage([10, 20, 30, 40, 50]), 30)
    }

    func testTrimmedAverageRoundsToNearestHundredth() {
        XCTAssertEqual(Stats.trimmedAverage([100, 100, 101, 0, 999]), 100) // 100.33
        XCTAssertEqual(Stats.trimmedAverage([100, 101, 101, 0, 999]), 101) // 100.67
    }

    func testAveragesNeedEnoughSolves() {
        let summary = Stats.summary([1500, 1400, 1300, 1200])
        XCTAssertEqual(summary.count, 4)
        XCTAssertEqual(summary.lastSingle, 1200)
        XCTAssertEqual(summary.bestSingle, 1200)
        XCTAssertNil(summary.ao5)
        XCTAssertNil(summary.bestAo5)
        XCTAssertNil(summary.ao12)
        XCTAssertNil(summary.bestAo12)
    }

    func testCurrentAndBestAo5() {
        // Windows: [10,20,30,40,50]=30, [20,30,40,50,60]=40, [30,40,50,60,5]=40, [40,50,60,5,100]=50
        let times = [10, 20, 30, 40, 50, 60, 5, 100]
        XCTAssertEqual(Stats.rollingAverages(times, size: 5), [nil, nil, nil, nil, 30, 40, 40, 50])
        let summary = Stats.summary(times)
        XCTAssertEqual(summary.ao5, 50)
        XCTAssertEqual(summary.bestAo5, 30)
        XCTAssertEqual(summary.bestSingle, 5)
        XCTAssertEqual(summary.lastSingle, 100)
    }

    func testCurrentAndBestAo12() {
        // 1...12 -> drop 1 and 12, mean of 2...11 = 6.5 -> rounds to 7.
        var times = Array(1...12)
        XCTAssertEqual(Stats.summary(times).ao12, 7)
        XCTAssertEqual(Stats.summary(times).bestAo12, 7)

        // Adding a slow solve: window is 2...12 + 500 -> drop 2 and 500, mean of 3...12 = 7.5 -> 8.
        times.append(500)
        XCTAssertEqual(Stats.summary(times).ao12, 8)
        XCTAssertEqual(Stats.summary(times).bestAo12, 7)
    }

    func testEmptyHistory() {
        XCTAssertEqual(Stats.summary([]), Stats.Summary())
    }
}

final class ScramblerTests: XCTestCase {
    private let axis: [Character: Int] = ["U": 0, "D": 0, "L": 1, "R": 1, "F": 2, "B": 2]

    func testScramblesAreWellFormed() {
        for _ in 0..<2000 {
            let moves = Scrambler.generate().split(separator: " ")
            XCTAssertEqual(moves.count, 20)
            for move in moves {
                XCTAssertNotNil(axis[move.first!], "unknown face in \(move)")
                XCTAssertTrue(["", "'", "2"].contains(String(move.dropFirst())), "bad suffix in \(move)")
            }
            let faces = moves.map { $0.first! }
            for i in 1..<faces.count {
                XCTAssertNotEqual(faces[i], faces[i - 1], "same face twice in a row")
            }
            for i in 2..<faces.count {
                let sameAxis = axis[faces[i]] == axis[faces[i - 1]] && axis[faces[i - 1]] == axis[faces[i - 2]]
                XCTAssertFalse(sameAxis, "three moves on one axis: \(moves[(i - 2)...i])")
            }
        }
    }

    func testRespectsLength() {
        XCTAssertEqual(Scrambler.generate(length: 25).split(separator: " ").count, 25)
    }
}

final class TimeFormatTests: XCTestCase {
    func testFormatting() {
        XCTAssertEqual(TimeFormat.string(centis: 0), "0.00")
        XCTAssertEqual(TimeFormat.string(centis: 7), "0.07")
        XCTAssertEqual(TimeFormat.string(centis: 1234), "12.34")
        XCTAssertEqual(TimeFormat.string(centis: 6000), "1:00.00")
        XCTAssertEqual(TimeFormat.string(centis: 7505), "1:15.05")
        XCTAssertEqual(TimeFormat.string(centis: 360_000 + 6105), "1:01:01.05")
    }

    func testTruncatesToHundredths() {
        XCTAssertEqual(TimeFormat.centis(seconds: 12.349), 1234)
        XCTAssertEqual(TimeFormat.centis(seconds: 0.999), 99)
        XCTAssertEqual(TimeFormat.centis(seconds: -1), 0)
    }
}

final class SolveStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("cubehub-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testSolvesSurviveReload() {
        let url = directory.appendingPathComponent("nested/solves.json")
        let store = SolveStore(url: url)
        let first = Solve(centis: 1234, scramble: "R U R' U'")
        let second = Solve(centis: 987, scramble: "F2 D")
        store.add(first)
        store.add(second)

        let reloaded = SolveStore(url: url)
        XCTAssertEqual(reloaded.solves.map(\.id), [first.id, second.id])
        XCTAssertEqual(reloaded.solves.map(\.centis), [1234, 987])
        XCTAssertEqual(reloaded.solves.map(\.scramble), ["R U R' U'", "F2 D"])

        reloaded.remove(id: first.id)
        XCTAssertEqual(SolveStore(url: url).solves.map(\.id), [second.id])

        reloaded.removeAll()
        XCTAssertTrue(SolveStore(url: url).solves.isEmpty)
    }

    func testUnreadableFileIsSetAsideNotOverwritten() throws {
        let url = directory.appendingPathComponent("solves.json")
        try Data("not json".utf8).write(to: url)

        let store = SolveStore(url: url)
        XCTAssertTrue(store.solves.isEmpty)
        store.add(Solve(centis: 100, scramble: "U"))

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let backup = try XCTUnwrap(names.first { $0.hasPrefix("solves.unreadable-") })
        let preserved = try String(contentsOf: directory.appendingPathComponent(backup), encoding: .utf8)
        XCTAssertEqual(preserved, "not json")
    }
}
