import Foundation

/// One-shot migration for the TransToast -> CCTrans rebrand (2026-06).
/// Old installs keep their settings and credentials by moving the legacy
/// directories to the new locations. Runs before any store reads disk,
/// and only when the legacy path exists and the new path does not.
enum LegacyBrandMigration {
    static func run(fileManager: FileManager = .default) {
        let home = fileManager.homeDirectoryForCurrentUser
        let pairs: [(legacy: URL, current: URL)] = [
            (
                home.appendingPathComponent(".config/transtoast", isDirectory: true),
                home.appendingPathComponent(".config/cctrans", isDirectory: true)
            ),
            (
                home.appendingPathComponent("Library/Application Support/as.kargn.transtoast", isDirectory: true),
                home.appendingPathComponent("Library/Application Support/as.kargn.cctrans", isDirectory: true)
            ),
        ]

        for pair in pairs {
            guard fileManager.fileExists(atPath: pair.legacy.path),
                  !fileManager.fileExists(atPath: pair.current.path) else {
                continue
            }
            do {
                try fileManager.createDirectory(
                    at: pair.current.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.moveItem(at: pair.legacy, to: pair.current)
                print("Migrated legacy data: \(pair.legacy.path) -> \(pair.current.path)")
            } catch {
                // Surface loudly: silent failure here would look like a settings wipe.
                print("Legacy data migration failed for \(pair.legacy.path): \(error.localizedDescription)")
            }
        }
    }
}
