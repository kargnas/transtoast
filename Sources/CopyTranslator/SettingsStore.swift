import CopyTranslatorCore
import Foundation

final class SettingsStore {
    private let key = "as.kargn.copy-translator.settings"
    private let defaults: UserDefaults

    var settings: TranslatorSettings {
        didSet {
            save()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(TranslatorSettings.self, from: data) {
            settings = decoded
        } else {
            settings = TranslatorSettings()
        }
    }

    private func save() {
        guard settings != TranslatorSettings() else {
            defaults.removeObject(forKey: key)
            return
        }

        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
