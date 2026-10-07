import Foundation

/// Solve history, persisted as JSON. Solves are kept oldest first.
public final class SolveStore {
    public private(set) var solves: [Solve] = []
    public let url: URL

    public init(url: URL) {
        self.url = url
        load()
    }

    /// ~/Library/Application Support/CubeHub/solves.json
    public static func defaultURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("CubeHub", isDirectory: true).appendingPathComponent("solves.json")
    }

    public func add(_ solve: Solve) {
        solves.append(solve)
        save()
    }

    public func remove(id: Solve.ID) {
        solves.removeAll { $0.id == id }
        save()
    }

    public func removeAll() {
        solves.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            solves = try decoder.decode([Solve].self, from: data)
        } catch {
            // Keep the unreadable file around rather than overwriting it on the next save.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = url.deletingLastPathComponent().appendingPathComponent("solves.unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: backup)
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(solves).write(to: url, options: .atomic)
        } catch {
            NSLog("CubeHub: could not save solves to %@: %@", url.path, String(describing: error))
        }
    }
}
