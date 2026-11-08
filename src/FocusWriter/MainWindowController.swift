import AppKit
import FocusWriterCore
import UniformTypeIdentifiers

private final class MenuActionTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke(_ sender: Any?) {
        action()
    }
}

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private enum EndReason {
        case complete
        case emergency
    }

    private let editorDocument: EditorDocument
    private let draftStore = DraftStore()
    private let inputBlocker = FocusInputBlocker()
    private let boundFileAccess = ScopedResourceAccess()
    private let secondaryImageAccess = ScopedResourceAccess()
    private var surface: EditorSurface!

    private let destinationLabel = NSTextField(labelWithString: "")
    private let startButton = NSButton()
    private let permissionButton = NSButton()
    private let themeButton = NSButton()
    private let wordCountLabel = NSTextField(labelWithString: "")
    private let stateLabel = NSTextField(labelWithString: "Auto-saves every 30 seconds")
    private var primaryThemeLabels: [NSTextField] = []
    private var secondaryThemeLabels: [NSTextField] = []
    private weak var themedContentView: NSView?
    private var selectedFolderURL: URL?
    private var selectedFileName: String
    private var boundFileURL: URL?
    private var selectedSecondaryMode: SecondaryDisplayMode = .systemWallpaper
    private var secondaryImageURL: URL?
    private var secondaryColor = NSColor(
        calibratedRed: 0.055,
        green: 0.075,
        blue: 0.09,
        alpha: 1
    )
    private var autoSaveTimer: Timer?
    private var focusOverlay: FocusOverlayController?
    private var previousPresentationOptions: NSApplication.PresentationOptions = []
    private var didPresentInitialFileChooser = false

    private(set) var isFocusActive = false

    init() {
        editorDocument = EditorDocument(text: DraftStore().load())
        selectedFileName = Self.defaultFileName()

        let fileManager = FileManager.default
        let fallbackFolder = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("WritingJail", isDirectory: true)
        let savedFolder = UserDefaults.standard.string(
            forKey: "lastMarkdownFolder"
        )
        let savedFolderURL = savedFolder.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        if let savedFolderURL,
            fileManager.fileExists(atPath: savedFolderURL.path) {
            selectedFolderURL = savedFolderURL
        } else {
            selectedFolderURL = fallbackFolder
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_040, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Writing Jail"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 900, height: 580)
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()

        super.init(window: window)
        window.delegate = self
        loadSecondaryDisplaySettings()
        buildInterface()
        observeDocument()
        startAutoSaveTimer()
        refreshPermissionStatus()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func adjustFontSize(by delta: CGFloat) {
        editorDocument.adjustFontSize(by: delta)
        stateLabel.stringValue = "Text size: \(Int(editorDocument.fontSize)) pt"
    }

    @objc private func toggleTheme(_ sender: Any?) {
        editorDocument.setTheme(editorDocument.theme.toggled)
        applyTheme()
        stateLabel.stringValue =
            editorDocument.theme == .dark ? "Dark mode active" : "Ivory mode active"
    }

    private func applyTheme() {
        let palette = editorDocument.palette
        window?.appearance = NSAppearance(named: editorDocument.theme.nsAppearance)
        themedContentView?.layer?.backgroundColor = palette.background.cgColor
        for label in primaryThemeLabels {
            label.textColor = palette.foreground
        }
        for label in secondaryThemeLabels {
            label.textColor = palette.secondaryText
        }
        themeButton.title = editorDocument.theme.switchButtonTitle
    }

    func saveDraftNow() {
        saveNow()
    }

    @discardableResult
    func presentInitialFileChooser() -> Bool {
        guard !didPresentInitialFileChooser, window != nil, !isFocusActive else {
            return false
        }
        didPresentInitialFileChooser = true

        let panel = NSOpenPanel()
        panel.title = "Choose a Markdown File"
        panel.prompt = "Choose"
        panel.message =
            "Select an existing Markdown file, or select a folder for a new document."
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText
        ]
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = selectedFolderURL

        let defaultName = MarkdownFileName.normalized(
            selectedFileName,
            fallback: Self.defaultFileName()
        ) ?? Self.defaultFileName()
        let filenameField = NSTextField(
            frame: NSRect(x: 0, y: 0, width: 280, height: 24)
        )
        filenameField.stringValue = defaultName
        let filenameLabel = NSTextField(labelWithString: "New file name")
        let createButton = NSButton(
            title: "Create New File…",
            target: nil,
            action: nil
        )
        createButton.bezelStyle = .rounded
        var createRequested = false
        let createTarget = MenuActionTarget {
            createRequested = true
            panel.cancel(nil)
        }
        createButton.target = createTarget
        createButton.action = #selector(MenuActionTarget.invoke(_:))

        let accessory = NSView(
            frame: NSRect(x: 0, y: 0, width: 540, height: 52)
        )
        filenameLabel.frame = NSRect(x: 12, y: 16, width: 96, height: 20)
        filenameField.frame = NSRect(x: 116, y: 13, width: 230, height: 26)
        createButton.frame = NSRect(x: 360, y: 10, width: 168, height: 32)
        accessory.addSubview(filenameLabel)
        accessory.addSubview(filenameField)
        accessory.addSubview(createButton)
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true

        let response = withExtendedLifetime(createTarget) {
            panel.runModal()
        }
        if createRequested {
            return presentNewFileFromStartup(
                defaultName: filenameField.stringValue
            )
        }
        guard response == .OK, let chosenURL = panel.url else {
            return false
        }
        boundFileAccess.retain(chosenURL)

        let isDirectory = (try? chosenURL.resourceValues(
            forKeys: [.isDirectoryKey]
        ).isDirectory) ?? false
        let selectedURL: URL
        if isDirectory {
            let fileName = MarkdownFileName.normalized(
                filenameField.stringValue,
                fallback: defaultName
            ) ?? defaultName
            selectedURL = chosenURL.appendingPathComponent(fileName)
        } else {
            selectedURL = chosenURL
        }

        applyInitialFileSelection(selectedURL)
        return true
    }

    private func presentNewFileFromStartup(defaultName: String) -> Bool {
        let panel = NSSavePanel()
        panel.title = "Create a New Markdown File"
        panel.prompt = "Create"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText
        ]
        panel.canCreateDirectories = true
        panel.directoryURL = selectedFolderURL
        panel.nameFieldStringValue = MarkdownFileName.normalized(
            defaultName,
            fallback: Self.defaultFileName()
        ) ?? Self.defaultFileName()

        guard panel.runModal() == .OK, let chosenURL = panel.url else {
            return false
        }
        boundFileAccess.retain(
            chosenURL.deletingLastPathComponent()
        )
        applyInitialFileSelection(chosenURL)
        return true
    }

    @objc func createNewFileFromMenu(_ sender: Any?) {
        guard !isFocusActive else {
            return
        }
        _ = presentNewFileFromStartup(
            defaultName: selectedFileName
        )
    }

    private func applyInitialFileSelection(_ chosenURL: URL) {
        let fileName = MarkdownFileName.normalized(
            chosenURL.lastPathComponent,
            fallback: Self.defaultFileName()
        ) ?? Self.defaultFileName()
        let folderURL = chosenURL.deletingLastPathComponent()
        rememberFolder(folderURL)
        selectedFileName = fileName

        let targetURL = folderURL.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            do {
                boundFileAccess.retain(
                    targetURL,
                    bookmarkKey: "boundMarkdownFileBookmark"
                )
                let text = try String(contentsOf: targetURL, encoding: .utf8)
                editorDocument.replaceText(text)
                surface.textView.undoManager?.removeAllActions()
                boundFileURL = targetURL
                stateLabel.stringValue =
                    "\(fileName) opened · Auto-saves every 30 seconds"
            } catch {
                showFileError(
                    title: "Unable to Read Existing File",
                    message: error.localizedDescription
                )
                return
            }
        } else {
            editorDocument.replaceText("")
            surface.textView.undoManager?.removeAllActions()
            draftStore.save("")
            do {
                try "".write(
                    to: targetURL,
                    atomically: true,
                    encoding: .utf8
                )
                boundFileAccess.retain(
                    targetURL,
                    bookmarkKey: "boundMarkdownFileBookmark"
                )
                boundFileURL = targetURL
                stateLabel.stringValue =
                    "\(fileName) created · Auto-saves every 30 seconds"
            } catch {
                boundFileURL = nil
                showFileError(
                    title: "Unable to Create File",
                    message: error.localizedDescription
                )
                return
            }
        }

        updateDestinationLabel()
        window?.makeFirstResponder(surface.textView)
    }

    @discardableResult
    func openInitialFile(at fileURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return false
        }
        applyInitialFileSelection(fileURL)
        return true
    }

    func refreshPermissionStatus() {
        guard !isFocusActive else {
            return
        }

        if FocusInputBlocker.hasAccessibilityPermission {
            permissionButton.title = "Input Blocking Ready"
            permissionButton.isEnabled = false
        } else {
            permissionButton.title = "Configure Input Blocking"
            permissionButton.isEnabled = true
        }
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else {
            return
        }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = EditorPalette.main.background.cgColor

        let titleLabel = NSTextField(labelWithString: "Writing Jail")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        primaryThemeLabels.append(titleLabel)

        permissionButton.bezelStyle = .inline
        permissionButton.controlSize = .small
        permissionButton.target = self
        permissionButton.action = #selector(configurePermission(_:))

        themeButton.bezelStyle = .inline
        themeButton.controlSize = .small
        themeButton.target = self
        themeButton.action = #selector(toggleTheme(_:))

        startButton.title = "Start Focus"
        startButton.bezelStyle = .rounded
        startButton.controlSize = .large
        startButton.keyEquivalent = "\r"
        startButton.target = self
        startButton.action = #selector(startFocus(_:))

        let topBar = NSStackView(
            views: [
                titleLabel,
                flexibleSpacer(),
                themeButton,
                permissionButton,
                startButton
            ]
        )
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 10

        destinationLabel.font = .systemFont(ofSize: 12)
        secondaryThemeLabels.append(destinationLabel)
        destinationLabel.lineBreakMode = .byTruncatingMiddle
        updateDestinationLabel()

        surface = EditorSurfaceFactory.make(
            document: editorDocument,
            palette: editorDocument.palette
        )

        wordCountLabel.font = .systemFont(ofSize: 12)
        secondaryThemeLabels.append(wordCountLabel)

        stateLabel.font = .systemFont(ofSize: 12)
        secondaryThemeLabels.append(stateLabel)

        let shortcutLabel = NSTextField(
            labelWithString: "Cmd +/− Text Size · Standard editing shortcuts enabled"
        )
        shortcutLabel.font = .systemFont(ofSize: 12)
        secondaryThemeLabels.append(shortcutLabel)

        let footer = NSStackView(
            views: [wordCountLabel, flexibleSpacer(), stateLabel, shortcutLabel]
        )
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 14

        for view in [
            topBar,
            destinationLabel,
            surface.scrollView,
            footer
        ] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            topBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            topBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            destinationLabel.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 14),
            destinationLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            destinationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            surface.scrollView.topAnchor.constraint(equalTo: destinationLabel.bottomAnchor, constant: 10),
            surface.scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            surface.scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            surface.scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),

            footer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
        ])

        updateWordCount()
        themedContentView = contentView
        applyTheme()
        window?.makeFirstResponder(surface.textView)
    }

    private func observeDocument() {
        NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification,
            object: editorDocument.textStorage,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.documentDidChange()
            }
        }
    }

    private func documentDidChange() {
        updateWordCount()
        stateLabel.stringValue = "Modified · Auto-saves every 30 seconds"
    }

    private func updateWordCount() {
        let text = editorDocument.text
        let words = text.split(whereSeparator: \.isWhitespace).count
        wordCountLabel.stringValue = "\(words) words · \(text.count) characters"
    }

    private func startAutoSaveTimer() {
        autoSaveTimer = Timer.scheduledTimer(
            withTimeInterval: 30,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.saveNow()
            }
        }
        if let autoSaveTimer {
            RunLoop.main.add(autoSaveTimer, forMode: .common)
        }
    }

    private var targetURL: URL? {
        guard
            let selectedFolderURL,
            let fileName = MarkdownFileName.normalized(
                selectedFileName,
                fallback: Self.defaultFileName()
            )
        else {
            return nil
        }
        return selectedFolderURL.appendingPathComponent(fileName, isDirectory: false)
    }

    func saveNow() {
        draftStore.save(editorDocument.text)
        let saveURL = isFocusActive ? targetURL : boundFileURL
        guard let saveURL else {
            stateLabel.stringValue = "Recovery draft saved · Select a file to start"
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: saveURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try editorDocument.text.write(
                to: saveURL,
                atomically: true,
                encoding: .utf8
            )
            if boundFileAccess.url?.standardizedFileURL
                != saveURL.standardizedFileURL {
                boundFileAccess.retain(
                    saveURL,
                    bookmarkKey: "boundMarkdownFileBookmark"
                )
            }
            boundFileURL = saveURL
            stateLabel.stringValue = "Auto-saved · \(Self.clockString())"
        } catch {
            stateLabel.stringValue = "Save failed: \(error.localizedDescription)"
        }
    }

    private func updateDestinationLabel() {
        if let targetURL {
            let isBound = boundFileURL?.standardizedFileURL == targetURL.standardizedFileURL
            let exists = FileManager.default.fileExists(atPath: targetURL.path)
            let state: String
            if isBound {
                state = "editing"
            } else if exists {
                state = "existing file · loaded on start"
            } else {
                state = "new file"
            }
            destinationLabel.stringValue =
                "Save file (\(state)): \(targetURL.lastPathComponent)"
            destinationLabel.toolTip = targetURL.path
        } else {
            destinationLabel.stringValue =
                "Choose a file or enter a file name before starting."
            destinationLabel.toolTip = nil
        }
    }

    private func loadSecondaryDisplaySettings() {
        selectedSecondaryMode =
            UserDefaults.standard.string(forKey: "secondaryDisplayMode")
            .flatMap(SecondaryDisplayMode.init(rawValue:))
            ?? .systemWallpaper

        if let restoredImageURL = secondaryImageAccess.restore(
            bookmarkKey: "secondaryDisplayImageBookmark",
            fallbackPathKey: "secondaryDisplayImagePath"
        ),
            FileManager.default.fileExists(atPath: restoredImageURL.path) {
            secondaryImageURL = restoredImageURL
        }

        if let savedColorData = UserDefaults.standard.data(
            forKey: "secondaryDisplayColor"
        ),
            let color = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSColor.self,
                from: savedColorData
            ) {
            secondaryColor = color
        }
    }

    func showSecondaryDisplayDialog() {
        guard NSScreen.screens.count > 1 else {
            return
        }

        let modePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for mode in SecondaryDisplayMode.allCases {
            modePopup.addItem(withTitle: mode.title)
        }
        modePopup.selectItem(
            at: SecondaryDisplayMode.allCases.firstIndex(
                of: selectedSecondaryMode
            ) ?? 1
        )
        let previousModeIndex = modePopup.indexOfSelectedItem

        let colorWell = NSColorWell()
        colorWell.color = secondaryColor

        let modeLabel = NSTextField(labelWithString: "Display content")
        let colorLabel = NSTextField(labelWithString: "Solid color")
        let hint = NSTextField(
            wrappingLabelWithString:
                "This setting applies to every secondary display. Selecting Custom Image opens an image picker immediately."
        )
        hint.textColor = .secondaryLabelColor
        var pendingImageURL = secondaryImageURL

        let modeActionTarget = MenuActionTarget {
            let index = modePopup.indexOfSelectedItem
            guard SecondaryDisplayMode.allCases.indices.contains(index) else {
                return
            }
            guard SecondaryDisplayMode.allCases[index] == .customImage else {
                return
            }

            let panel = NSOpenPanel()
            panel.title = "Choose an Image for Secondary Displays"
            panel.prompt = "Choose"
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [.image]

            guard panel.runModal() == .OK, let imageURL = panel.url else {
                modePopup.selectItem(at: previousModeIndex)
                return
            }
            pendingImageURL = imageURL
            hint.stringValue = "Selected image: \(imageURL.lastPathComponent)"
        }
        modePopup.target = modeActionTarget
        modePopup.action = #selector(MenuActionTarget.invoke(_:))

        let modeRow = NSStackView(views: [modeLabel, modePopup])
        modeRow.orientation = .horizontal
        modeRow.alignment = .centerY
        modeRow.spacing = 12

        let colorRow = NSStackView(views: [colorLabel, colorWell])
        colorRow.orientation = .horizontal
        colorRow.alignment = .centerY
        colorRow.spacing = 12

        let accessory = NSStackView(views: [modeRow, colorRow, hint])
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 10
        accessory.frame = NSRect(x: 0, y: 0, width: 420, height: 112)

        let alert = NSAlert()
        alert.messageText = "Secondary Display"
        alert.informativeText =
            "Choose what Writing Jail should show on secondary displays."
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        let response = withExtendedLifetime(modeActionTarget) {
            alert.runModal()
        }
        guard response == .alertFirstButtonReturn else {
            return
        }

        let index = modePopup.indexOfSelectedItem
        guard SecondaryDisplayMode.allCases.indices.contains(index) else {
            return
        }
        let selectedMode = SecondaryDisplayMode.allCases[index]

        if selectedMode == .customImage {
            guard let imageURL = pendingImageURL else {
                stateLabel.stringValue =
                    "Select an image before applying Custom Image."
                return
            }
            secondaryImageURL = imageURL
            secondaryImageAccess.retain(
                imageURL,
                bookmarkKey: "secondaryDisplayImageBookmark"
            )
            UserDefaults.standard.set(
                imageURL.path,
                forKey: "secondaryDisplayImagePath"
            )
        } else if selectedMode == .solidColor {
            secondaryColor = colorWell.color
            if let data = try? NSKeyedArchiver.archivedData(
                withRootObject: secondaryColor,
                requiringSecureCoding: true
            ) {
                UserDefaults.standard.set(
                    data,
                    forKey: "secondaryDisplayColor"
                )
            }
        }

        selectedSecondaryMode = selectedMode
        UserDefaults.standard.set(
            selectedMode.rawValue,
            forKey: "secondaryDisplayMode"
        )
        stateLabel.stringValue = "Secondary display set to \(selectedMode.title)"
    }

    @objc private func openExistingFile(_ sender: Any?) {
        saveNow()

        let panel = NSOpenPanel()
        panel.title = "Open Markdown File"
        panel.prompt = "Open"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText
        ]
        if let selectedFolderURL {
            panel.directoryURL = selectedFolderURL
        }

        guard panel.runModal() == .OK, let fileURL = panel.url else {
            return
        }

        do {
            boundFileAccess.retain(
                fileURL,
                bookmarkKey: "boundMarkdownFileBookmark"
            )
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            editorDocument.replaceText(text)
            surface.textView.undoManager?.removeAllActions()
            rememberFolder(fileURL.deletingLastPathComponent())
            boundFileURL = fileURL
            selectedFileName = fileURL.lastPathComponent
            updateDestinationLabel()
            stateLabel.stringValue =
                "\(fileURL.lastPathComponent) opened · Auto-saves every 30 seconds"
            window?.makeFirstResponder(surface.textView)
        } catch {
            showFileError(
                title: "Unable to Open File",
                message: error.localizedDescription
            )
        }
    }

    @objc func openFileFromMenu(_ sender: Any?) {
        openExistingFile(sender)
    }

    private func resolveTargetURLForFocus() -> URL? {
        if selectedFolderURL != nil {
            guard let fileName = MarkdownFileName.normalized(
                selectedFileName,
                fallback: Self.defaultFileName()
            ) else {
                showFileError(
                    title: "Check the File Name",
                    message: "File names cannot contain /. The file will be saved as .md."
                )
                return nil
            }
            selectedFileName = fileName
            updateDestinationLabel()
            return selectedFolderURL?.appendingPathComponent(fileName, isDirectory: false)
        }

        let panel = NSOpenPanel()
        panel.title = "Choose a Markdown File"
        panel.prompt = "Open"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText
        ]

        guard panel.runModal() == .OK, let chosenURL = panel.url else {
            return nil
        }

        rememberFolder(chosenURL.deletingLastPathComponent())
        selectedFileName = chosenURL.lastPathComponent
        updateDestinationLabel()
        return chosenURL
    }

    private func rememberFolder(_ folderURL: URL) {
        selectedFolderURL = folderURL
        UserDefaults.standard.set(
            folderURL.path,
            forKey: "lastMarkdownFolder"
        )
    }

    private func prepareTargetForFocus(_ targetURL: URL) -> Bool {
        let isSameFile =
            boundFileURL?.standardizedFileURL == targetURL.standardizedFileURL
        let fileExists = FileManager.default.fileExists(atPath: targetURL.path)
        if fileExists {
            boundFileAccess.retain(
                targetURL,
                bookmarkKey: "boundMarkdownFileBookmark"
            )
        } else {
            boundFileAccess.retain(targetURL.deletingLastPathComponent())
        }

        if !isSameFile {
            saveNow()
        }

        if fileExists && !isSameFile {
            do {
                let text = try String(contentsOf: targetURL, encoding: .utf8)
                editorDocument.replaceText(text)
                surface.textView.undoManager?.removeAllActions()
                boundFileURL = targetURL
                stateLabel.stringValue =
                    "\(targetURL.lastPathComponent) loaded from disk"
            } catch {
                showFileError(
                    title: "Unable to Read Existing File",
                    message: "\(targetURL.path)\n\n\(error.localizedDescription)"
                )
                return false
            }
        } else {
            boundFileURL = targetURL
        }

        updateDestinationLabel()
        return true
    }

    private func showFileError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "focus-\(formatter.string(from: Date())).md"
    }

    private static func clockString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    @objc private func startFocus(_ sender: Any?) {
        guard !isFocusActive else {
            return
        }
        guard let duration = requestFocusDuration() else {
            return
        }
        guard let targetURL = resolveTargetURLForFocus() else {
            return
        }
        guard prepareTargetForFocus(targetURL) else {
            return
        }

        if !FocusInputBlocker.hasAccessibilityPermission {
            let alert = NSAlert()
            alert.messageText = "Input Blocking Permission Required"
            alert.informativeText =
                "Accessibility permission lets Writing Jail block shortcuts such as Cmd-Tab and Mission Control. Without it, only the in-app kiosk lock is applied."
            alert.addButton(withTitle: "Start Limited Mode")
            alert.addButton(withTitle: "Configure Input Blocking")
            alert.addButton(withTitle: "Cancel")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                break
            case .alertSecondButtonReturn:
                configurePermission(nil)
                return
            default:
                return
            }
        }

        beginFocus(duration: duration, targetURL: targetURL)
    }

    private func requestFocusDuration() -> FocusDuration? {
        while true {
            let durationLabel = NSTextField(labelWithString: "Duration (minutes)")
            let durationPopup = NSPopUpButton(
                frame: NSRect(x: 0, y: 0, width: 120, height: 26),
                pullsDown: false
            )
            for minutes in FocusDuration.minuteOptions {
                durationPopup.addItem(
                    withTitle: FocusDuration.label(minutes: minutes)
                )
                durationPopup.lastItem?.representedObject = minutes
            }
            durationPopup.selectItem(at: 0)

            let accessory = NSView(
                frame: NSRect(x: 0, y: 0, width: 290, height: 34)
            )
            durationLabel.frame = NSRect(x: 0, y: 8, width: 132, height: 20)
            durationPopup.frame = NSRect(x: 140, y: 3, width: 140, height: 28)
            accessory.addSubview(durationLabel)
            accessory.addSubview(durationPopup)

            let alert = NSAlert()
            alert.messageText = "Start Focus Session"
            alert.informativeText = "Choose how long you want to stay focused."
            alert.accessoryView = accessory
            alert.addButton(withTitle: "Start")
            alert.addButton(withTitle: "Cancel")

            guard alert.runModal() == .alertFirstButtonReturn else {
                return nil
            }
            guard
                let selectedMinutes = durationPopup.selectedItem?
                    .representedObject as? Int,
                let duration = FocusDuration(input: String(selectedMinutes)) else {
                continue
            }

            if duration.seconds >= 30 * 60 {
                let confirmation = NSAlert()
                confirmation.messageText = "Confirm Long Focus Session"
                confirmation.informativeText =
                    "This session will last \(duration.displayMinutes) minutes. You will not be able to leave Writing Jail until the timer ends."
                confirmation.addButton(withTitle: "Start Session")
                confirmation.addButton(withTitle: "Change Duration")
                if confirmation.runModal() != .alertFirstButtonReturn {
                    continue
                }
            }
            return duration
        }
    }

    private func beginFocus(duration: FocusDuration, targetURL: URL) {
        saveDraftNow()
        isFocusActive = true
        previousPresentationOptions = NSApp.presentationOptions

        let overlay = FocusOverlayController(
            document: editorDocument,
            duration: duration.seconds,
            destinationName: targetURL.lastPathComponent,
            secondaryMode: selectedSecondaryMode,
            secondaryImageURL: secondaryImageURL,
            secondaryColor: secondaryColor
        ) { [weak self] in
            self?.endFocus(reason: .complete)
        }
        focusOverlay = overlay
        overlay.present()

        NSApp.presentationOptions = [
            .disableProcessSwitching,
            .hideDock,
            .hideMenuBar,
            .disableAppleMenu,
            .disableForceQuit,
            .disableHideApplication,
            .disableSessionTermination,
            .disableMenuBarTransparency
        ]

        inputBlocker.onEmergencyUnlock = { [weak self] in
            self?.endFocus(reason: .emergency)
        }
        if !inputBlocker.start() {
            stateLabel.stringValue = "System shortcut blocking could not start"
        } else {
            stateLabel.stringValue = "Maximum focus lock active"
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.orderOut(nil)
    }

    private func endFocus(reason: EndReason) {
        guard isFocusActive else {
            return
        }

        inputBlocker.stop()
        inputBlocker.onEmergencyUnlock = nil
        NSApp.presentationOptions = previousPresentationOptions
        saveDraftNow()

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        focusOverlay?.dismiss()
        focusOverlay = nil
        isFocusActive = false

        stateLabel.stringValue = reason == .complete
            ? "Focus complete · Saved"
            : "Emergency exit · Saved"
        applyTheme()
        refreshPermissionStatus()

        window?.makeFirstResponder(surface.textView)
    }

    @objc private func configurePermission(_ sender: Any?) {
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            presentManualAccessibilityInstructions()
            return
        }
        FocusInputBlocker.requestAccessibilityPermission()
        FocusInputBlocker.openAccessibilitySettings()
    }

    private func presentManualAccessibilityInstructions() {
        let appPath = Bundle.main.bundleURL.path
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(appPath, forType: .string)

        let alert = NSAlert()
        alert.messageText = "Enable Input Blocking"
        alert.informativeText =
            "macOS 27 requires Accessibility access to be added manually. In Device Control and Data Access, click + and choose WritingJail.app. The app path has been copied to the clipboard."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        FocusInputBlocker.openAccessibilitySettings()
    }

    func stopScopedResourceAccess() {
        boundFileAccess.release()
        secondaryImageAccess.release()
    }

    private func flexibleSpacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

}
