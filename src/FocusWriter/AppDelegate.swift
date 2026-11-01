import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var keyMonitor: Any?
    private var secondaryDisplayMenuItem: NSMenuItem?
    private var screenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()

        let controller = MainWindowController()
        mainWindowController = controller
        NSApp.activate(ignoringOtherApps: true)
        updateSecondaryDisplayMenuAvailability()

        if let startupFile = startupFileArgument(),
            controller.openInitialFile(at: startupFile) {
            controller.showWindow(nil)
        } else {
            DispatchQueue.main.async {
                guard controller.presentInitialFileChooser() else {
                    NSApp.terminate(nil)
                    return
                }
                controller.showWindow(nil)
            }
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateSecondaryDisplayMenuAvailability()
            }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command) else {
                return event
            }

            switch event.keyCode {
            case 24, 69:
                self?.mainWindowController?.adjustFontSize(by: 2)
                return nil
            case 27, 78:
                self?.mainWindowController?.adjustFontSize(by: -2)
                return nil
            default:
                return event
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        mainWindowController?.refreshPermissionStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainWindowController?.saveDraftNow()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        !(mainWindowController?.isFocusActive ?? false)
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        (mainWindowController?.isFocusActive ?? false) ? .terminateCancel : .terminateNow
    }

    @objc private func zoomIn(_ sender: Any?) {
        mainWindowController?.adjustFontSize(by: 2)
    }

    @objc private func zoomOut(_ sender: Any?) {
        mainWindowController?.adjustFontSize(by: -2)
    }

    @objc private func openFileFromMenu(_ sender: Any?) {
        mainWindowController?.openFileFromMenu(sender)
    }

    @objc private func createNewFileFromMenu(_ sender: Any?) {
        mainWindowController?.createNewFileFromMenu(sender)
    }

    @objc private func showSecondaryDisplay(_ sender: Any?) {
        mainWindowController?.showSecondaryDisplayDialog()
    }

    private func updateSecondaryDisplayMenuAvailability() {
        secondaryDisplayMenuItem?.isHidden = NSScreen.screens.count < 2
    }

    private func startupFileArgument() -> URL? {
        for argument in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: argument)
            guard
                ["md", "markdown"].contains(url.pathExtension.lowercased()),
                FileManager.default.fileExists(atPath: url.path)
            else {
                continue
            }
            return url
        }
        return nil
    }

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: "Writing Jail")
        appItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "About Writing Jail",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Writing Jail",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(
            withTitle: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        let redo = editMenu.addItem(
            withTitle: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        )
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editMenu.addItem(.separator())
        let openFile = editMenu.addItem(
            withTitle: "Open File…",
            action: #selector(openFileFromMenu(_:)),
            keyEquivalent: "o"
        )
        openFile.target = self
        let newFile = editMenu.addItem(
            withTitle: "New File…",
            action: #selector(createNewFileFromMenu(_:)),
            keyEquivalent: "n"
        )
        newFile.target = self

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        viewMenu.addItem(
            withTitle: "Increase Text Size",
            action: #selector(zoomIn(_:)),
            keyEquivalent: "+"
        ).target = self
        viewMenu.addItem(
            withTitle: "Decrease Text Size",
            action: #selector(zoomOut(_:)),
            keyEquivalent: "-"
        ).target = self
        viewMenu.addItem(.separator())
        let secondaryDisplay = viewMenu.addItem(
            withTitle: "Secondary Display…",
            action: #selector(showSecondaryDisplay(_:)),
            keyEquivalent: ""
        )
        secondaryDisplay.target = self
        secondaryDisplayMenuItem = secondaryDisplay

        return mainMenu
    }
}
