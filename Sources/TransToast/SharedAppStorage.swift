import Foundation

enum SharedAppStorage {
    static let appIdentifier = "as.kargn.transtoast"

    static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appIdentifier, isDirectory: true)
    }

    static func fileURL(_ name: String) -> URL {
        directoryURL.appendingPathComponent(name, isDirectory: false)
    }

    static func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }
}
