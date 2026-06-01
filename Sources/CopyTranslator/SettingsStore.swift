import CopyTranslatorCore
import Foundation

final class SettingsStore {
    private let key = "as.kargn.copy-translator.settings"
    private let defaults: UserDefaults
    private let settingsURL = SharedAppStorage.fileURL("settings-overrides.json")

    var settings: TranslatorSettings {
        didSet {
            save()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = try? Data(contentsOf: settingsURL),
           let decoded = try? JSONDecoder().decode(TranslatorSettings.self, from: data) {
            settings = decoded
        } else if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(TranslatorSettings.self, from: data) {
            settings = decoded
            save()
        } else {
            settings = TranslatorSettings()
        }
    }

    private func save() {
        guard settings != TranslatorSettings() else {
            defaults.removeObject(forKey: key)
            try? FileManager.default.removeItem(at: settingsURL)
            return
        }

        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        do {
            try SharedAppStorage.ensureDirectoryExists()
            try data.write(to: settingsURL, options: .atomic)
            defaults.removeObject(forKey: key)
        } catch {
            defaults.set(data, forKey: key)
        }
    }
}
