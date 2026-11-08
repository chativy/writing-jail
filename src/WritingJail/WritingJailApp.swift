import AppKit

@main
enum WritingJailApp {
    @MainActor
    static func main() {
        LegacySettingsMigrator.migrate()

        let application = NSApplication.shared
        let appDelegate = WritingJailAppDelegate()
        application.delegate = appDelegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}
