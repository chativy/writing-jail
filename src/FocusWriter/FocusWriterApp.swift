import AppKit

@main
enum WritingJailApp {
    @MainActor
    static func main() {
        migrateLegacySettings()

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }

    private static func migrateLegacySettings() {
        let legacyBundleID = "local.focuswriter.app"
        guard let legacyValues = UserDefaults.standard.persistentDomain(
            forName: legacyBundleID
        ) else {
            return
        }

        let keys = [
            "editorFontSize",
            "secondaryDisplayMode",
            "secondaryDisplayImagePath",
            "secondaryDisplayColor",
            "lastMarkdownFolder",
            "editorTheme"
        ]
        for key in keys where UserDefaults.standard.object(forKey: key) == nil {
            if let value = legacyValues[key] {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
    }
}
