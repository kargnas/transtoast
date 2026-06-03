import CopyTranslatorCore
import Foundation

struct RequestLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let source: String
    let providerTitle: String
    let model: String
    let inputPreview: String
    let outputPreview: String
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let costCredits: Double?
    let usageSource: String
    let isDuplicateSuspect: Bool
    let imageInfo: String?
    let fingerprint: String
}

struct RequestLogSummary {
    let requestCount: Int
    let duplicateSuspectCount: Int
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let costCredits: Double
}

@MainActor
final class RequestLogStore {
    private(set) var entries: [RequestLogEntry] = []
    private let maxEntries = 200
    private let duplicateWindow: TimeInterval = 2
    private let storageURL = SharedAppStorage.fileURL("request-logs.json")

    @discardableResult
    func add(
        source: String,
        input: String,
        result: TranslationResult,
        imageInfo: String?
    ) -> RequestLogEntry {
        let now = Date()
        let fingerprint = normalizedFingerprint(input)
        let promptTokens = result.usage?.promptTokens ?? estimatedTokenCount(input)
        let completionTokens = result.usage?.completionTokens ?? estimatedTokenCount(result.text)
        let totalTokens = result.usage?.totalTokens ?? promptTokens + completionTokens
        let costCredits = result.usage?.costCredits
        let isDuplicate = entries.contains { entry in
            now.timeIntervalSince(entry.timestamp) <= duplicateWindow
                && entry.source == source
                && entry.model == result.model
                && entry.fingerprint == fingerprint
        }

        let entry = RequestLogEntry(
            timestamp: now,
            source: source,
            providerTitle: result.providerTitle,
            model: result.model,
            inputPreview: preview(input),
            outputPreview: preview(result.text),
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens,
            costCredits: costCredits,
            usageSource: result.usage == nil ? "estimated" : "actual",
            isDuplicateSuspect: isDuplicate,
            imageInfo: imageInfo,
            fingerprint: fingerprint
        )
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        save()
        return entry
    }

    func clear() {
        entries.removeAll()
        save()
    }

    var summary: RequestLogSummary {
        RequestLogSummary(
            requestCount: entries.count,
            duplicateSuspectCount: entries.filter(\.isDuplicateSuspect).count,
            promptTokens: entries.reduce(0) { $0 + $1.promptTokens },
            completionTokens: entries.reduce(0) { $0 + $1.completionTokens },
            totalTokens: entries.reduce(0) { $0 + $1.totalTokens },
            costCredits: entries.reduce(0) { $0 + ($1.costCredits ?? 0) }
        )
    }

    private func normalizedFingerprint(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .prefixString(1_000)
    }

    private func preview(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .prefixString(180)
    }

    private func estimatedTokenCount(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return 0
        }
        return max(1, Int(ceil(Double(trimmed.count) / 4.0)))
    }

    private func save() {
        let file = RequestLogFile(entries: entries.map(RequestLogDiskEntry.init))
        do {
            try SharedAppStorage.ensureDirectoryExists()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Could not save request logs: \(error.localizedDescription)")
        }
    }
}

private struct RequestLogFile: Encodable {
    let entries: [RequestLogDiskEntry]
}

private struct RequestLogDiskEntry: Encodable {
    let id: String
    let timestamp: String
    let source: String
    let providerTitle: String
    let model: String
    let inputPreview: String
    let outputPreview: String
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let costCredits: Double?
    let usageSource: String
    let isDuplicateSuspect: Bool
    let imageInfo: String?
    let fingerprint: String

    init(_ entry: RequestLogEntry) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        id = entry.id.uuidString
        timestamp = formatter.string(from: entry.timestamp)
        source = entry.source
        providerTitle = entry.providerTitle
        model = entry.model
        inputPreview = entry.inputPreview
        outputPreview = entry.outputPreview
        promptTokens = entry.promptTokens
        completionTokens = entry.completionTokens
        totalTokens = entry.totalTokens
        costCredits = entry.costCredits
        usageSource = entry.usageSource
        isDuplicateSuspect = entry.isDuplicateSuspect
        imageInfo = entry.imageInfo
        fingerprint = entry.fingerprint
    }
}

private extension StringProtocol {
    func prefixString(_ maxLength: Int) -> String {
        let clipped = prefix(maxLength)
        return count > maxLength ? "\(clipped)..." : String(clipped)
    }
}
