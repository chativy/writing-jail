import Foundation

enum LegacySettingsMigrator {
    private static let legacyBundleIdentifier = "local.focuswriter.app"

    static func migrate() {
        guard let legacyValues = UserDefaults.standard.persistentDomain(
            forName: legacyBundleIdentifier
        ) else {
            return
        }

        let settingKeys = [
            "editorFontSize",
            "secondaryDisplayMode",
            "secondaryDisplayImagePath",
            "secondaryDisplayColor",
            "lastMarkdownFolder",
            "editorTheme",
            "defaultFileNameFormat"
        ]
        for settingKey in settingKeys
        where UserDefaults.standard.object(forKey: settingKey) == nil {
            if let legacyValue = legacyValues[settingKey] {
                UserDefaults.standard.set(legacyValue, forKey: settingKey)
            }
        }
    }
}
