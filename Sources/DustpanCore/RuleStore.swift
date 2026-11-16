import Foundation

/// Loads cleanup rules. Built-in rules ship with the app; users can add or override
/// rules by dropping JSON files into `~/Library/Application Support/Dustpan/Rules`.
public enum RuleStore {
    public static var userRulesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dustpan/Rules", isDirectory: true)
    }

    public static func builtIn() -> [Rule] {
        guard let directory = Bundle.module.url(forResource: "Rules", withExtension: nil) else { return [] }
        return load(from: directory)
    }

    /// Built-in rules, with user rules added. A user rule with the same id replaces the built-in one.
    public static func all() -> [Rule] {
        var byID: [String: Rule] = [:]
        var order: [String] = []
        for rule in builtIn() + load(from: userRulesDirectory) {
            if byID[rule.id] == nil { order.append(rule.id) }
            byID[rule.id] = rule
        }
        return order.compactMap { byID[$0] }
    }

    /// Each `.json` file holds an array of rules. Files that fail to decode are skipped.
    public static func load(from directory: URL) -> [Rule] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { file -> [Rule] in
                guard let data = try? Data(contentsOf: file) else { return [] }
                return (try? decoder.decode([Rule].self, from: data)) ?? []
            }
    }
}
