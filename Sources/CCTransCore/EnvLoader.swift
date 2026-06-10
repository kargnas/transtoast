import Foundation

public enum EnvLoader {
    public static func load(paths: [URL]) -> [String: String] {
        var values: [String: String] = [:]

        for path in paths where FileManager.default.fileExists(atPath: path.path) {
            guard let contents = try? String(contentsOf: path, encoding: .utf8) else {
                continue
            }

            for line in contents.components(separatedBy: .newlines) {
                guard let pair = parseLine(line) else {
                    continue
                }
                values[pair.key] = pair.value
            }
        }

        return values
    }

    public static func mergedEnvironment(dotenv: [String: String]) -> [String: String] {
        var merged = dotenv
        for (key, value) in ProcessInfo.processInfo.environment {
            merged[key] = value
        }
        return merged
    }

    public static func parseLine(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
            return nil
        }

        let normalized = trimmed.hasPrefix("export ")
            ? String(trimmed.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            : trimmed

        guard let equalsIndex = normalized.firstIndex(of: "=") else {
            return nil
        }

        let key = normalized[..<equalsIndex].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            return nil
        }

        let rawValue = normalized[normalized.index(after: equalsIndex)...].trimmingCharacters(in: .whitespaces)
        return (key, unquote(rawValue))
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else {
            return value
        }

        if value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }

        if value.hasPrefix("'"), value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
        }

        return value
    }
}
