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
        var didMigrate = false
        if let data = defaults.data(forKey: key),
           var decoded = try? JSONDecoder().decode(TranslatorSettings.self, from: data) {
            didMigrate = decoded.migrateLegacyDefaultOpenRouterModels()
            settings = decoded
        } else {
            settings = TranslatorSettings()
        }
        if didMigrate {
            save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
