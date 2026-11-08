import AppKit
import WritingJailCore
import UniformTypeIdentifiers

@MainActor
final class WritingJailWindowController: NSWindowController, NSWindowDelegate {
    private enum EndReason {
        case complete
        case emergency
    }

    private let editorTextModel: EditorTextModel
    private let recoveryDraftStore = RecoveryDraftStore()
    private let keyboardBlocker = FocusKeyboardBlocker()
    private let documentFileAccess = SecurityScopedResourceAccess()
    private let secondaryImageAccess = SecurityScopedResourceAccess()
    private var editorSurface: EditorSurface!

    private let documentLocationLabel = NSTextField(labelWithString: "")
    private let startFocusButton = NSButton()
    private let accessibilityPermissionButton = NSButton()
    private let themeToggleButton = NSButton()
    private let wordCountLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "Auto-saves every 30 seconds")
    private var primaryTextLabels: [NSTextField] = []
    private var mutedTextLabels: [NSTextField] = []
    private weak var themedContentView: NSView?
    private var documentDirectoryURL: URL?
    private var documentFileName: String
    private var currentDocumentURL: URL?
    private var secondaryDisplayMode: SecondaryDisplayMode = .systemWallpaper
    private var secondaryImageURL: URL?
    private var secondaryColor = NSColor(
        calibratedRed: 0.055,
        green: 0.075,
        blue: 0.09,
        alpha: 1
    )
    private var autoSaveTimer: Timer?
    private var focusOverlayController: FocusSessionOverlayController?
    private var preFocusPresentationOptions: NSApplication.PresentationOptions = []
    private var hasPresentedInitialDocumentChooser = false

    private(set) var isFocusSessionActive = false

    init() {
        editorTextModel = EditorTextModel(text: RecoveryDraftStore().loadText())
        documentFileName = Self.suggestedFileName()

        let fileManager = FileManager.default
        let fallbackDirectoryURL = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("WritingJail", isDirectory: true)
        let storedDirectoryPath = UserDefaults.standard.string(
            forKey: "lastMarkdownFolder"
        )
        let storedDirectoryURL = storedDirectoryPath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        if let storedDirectoryURL,
            fileManager.fileExists(atPath: storedDirectoryURL.path) {
            documentDirectoryURL = storedDirectoryURL
        } else {
            documentDirectoryURL = fallbackDirectoryURL
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
        restoreSecondaryDisplaySettings()
        buildUserInterface()
        observeDocumentChanges()
        scheduleAutoSaveTimer()
        refreshAccessibilityPermissionStatus()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func changeFontSize(by delta: CGFloat) {
        editorTextModel.changeFontSize(by: delta)
        statusLabel.stringValue = "Text size: \(Int(editorTextModel.fontSize)) pt"
    }

    @objc private func toggleTheme(_ sender: Any?) {
        editorTextModel.applyTheme(editorTextModel.theme.opposite)
        applyTheme()
        statusLabel.stringValue =
            editorTextModel.theme == .dark ? "Dark mode active" : "Ivory mode active"
    }

    private func applyTheme() {
        let palette = editorTextModel.palette
        window?.appearance = NSAppearance(named: editorTextModel.theme.systemAppearance)
        themedContentView?.layer?.backgroundColor = palette.background.cgColor
        for label in primaryTextLabels {
            label.textColor = palette.foreground
        }
        for label in mutedTextLabels {
            label.textColor = palette.secondaryText
        }
        themeToggleButton.title = editorTextModel.theme.toggleButtonTitle
    }

    @discardableResult
    func presentInitialDocumentChooser() -> Bool {
        guard !hasPresentedInitialDocumentChooser, window != nil, !isFocusSessionActive else {
            return false
        }
        hasPresentedInitialDocumentChooser = true

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
        panel.directoryURL = documentDirectoryURL

        let suggestedName = MarkdownFilename.normalizedFilename(
            documentFileName,
            fallback: Self.suggestedFileName()
        ) ?? Self.suggestedFileName()
        let filenameField = NSTextField(
            frame: NSRect(x: 0, y: 0, width: 280, height: 24)
        )
        filenameField.stringValue = suggestedName
        let filenameLabel = NSTextField(labelWithString: "New file name")
        let createButton = NSButton(
            title: "Create New File…",
            target: nil,
            action: nil
        )
        createButton.bezelStyle = .rounded
        var createRequested = false
        let createActionTarget = ClosureActionTarget {
            createRequested = true
            panel.cancel(nil)
        }
        createButton.target = createActionTarget
        createButton.action = #selector(ClosureActionTarget.invoke(_:))

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

        let alertResponse = withExtendedLifetime(createActionTarget) {
            panel.runModal()
        }
        if createRequested {
            return presentNewDocumentPanel(
                suggestedName: filenameField.stringValue
            )
        }
        guard alertResponse == .OK, let chosenURL = panel.url else {
            return false
        }
        documentFileAccess.retainAccess(to: chosenURL)

        let chosenPathIsDirectory = (try? chosenURL.resourceValues(
            forKeys: [.isDirectoryKey]
        ).isDirectory) ?? false
        let documentURLToOpen: URL
        if chosenPathIsDirectory {
            let fileName = MarkdownFilename.normalizedFilename(
                filenameField.stringValue,
                fallback: suggestedName
            ) ?? suggestedName
            documentURLToOpen = chosenURL.appendingPathComponent(fileName)
        } else {
            documentURLToOpen = chosenURL
        }

        loadOrCreateDocument(documentURLToOpen)
        return true
    }

    private func presentNewDocumentPanel(suggestedName: String) -> Bool {
        let panel = NSSavePanel()
        panel.title = "Create a New Markdown File"
        panel.prompt = "Create"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText
        ]
        panel.canCreateDirectories = true
        panel.directoryURL = documentDirectoryURL
        panel.nameFieldStringValue = MarkdownFilename.normalizedFilename(
            suggestedName,
            fallback: Self.suggestedFileName()
        ) ?? Self.suggestedFileName()

        guard panel.runModal() == .OK, let chosenURL = panel.url else {
            return false
        }
        documentFileAccess.retainAccess(
            to:
            chosenURL.deletingLastPathComponent()
        )
        loadOrCreateDocument(chosenURL)
        return true
    }

    @objc func createNewDocumentFromMenu(_ sender: Any?) {
        guard !isFocusSessionActive else {
            return
        }
        _ = presentNewDocumentPanel(
            suggestedName: Self.suggestedFileName()
        )
    }

    @objc func configureDefaultFilenameTemplate(_ sender: Any?) {
        guard !isFocusSessionActive else {
            return
        }

        let storedTemplate = UserDefaults.standard.string(
            forKey: Self.defaultFilenameTemplateKey
        ) ?? DefaultFilenameTemplate.defaultTemplate
        let templateTextField = NSTextField(
            frame: NSRect(x: 0, y: 0, width: 430, height: 26)
        )
        templateTextField.stringValue = storedTemplate
        templateTextField.placeholderString = DefaultFilenameTemplate.defaultTemplate

        let exampleFileName = DefaultFilenameTemplate.makeFilename(
            template: storedTemplate,
            date: Date()
        ) ?? "focus.md"
        let instructionsLabel = NSTextField(
            wrappingLabelWithString:
                "Tokens: {date}, {time}, {datetime}, {yyyy}, {MM}, {dd}, {HH}, {mm}, {ss}. The .md extension is added automatically. Example: \(exampleFileName)"
        )
        instructionsLabel.textColor = .secondaryLabelColor

        let accessory = NSView(
            frame: NSRect(x: 0, y: 0, width: 520, height: 92)
        )
        templateTextField.frame = NSRect(x: 0, y: 56, width: 500, height: 26)
        instructionsLabel.frame = NSRect(x: 0, y: 0, width: 500, height: 48)
        accessory.addSubview(templateTextField)
        accessory.addSubview(instructionsLabel)

        let alert = NSAlert()
        alert.messageText = "Default File Name Format"
        alert.informativeText =
            "Choose the file name pattern used for new Markdown documents."
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let template = templateTextField.stringValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let preview = DefaultFilenameTemplate.makeFilename(
            template: template,
            date: Date()
        ) else {
            presentFileError(
                title: "Invalid File Name Format",
                message:
                    "Enter a non-empty format without /. The .md extension is added automatically."
            )
            return
        }

        UserDefaults.standard.set(
            template,
            forKey: Self.defaultFilenameTemplateKey
        )
        statusLabel.stringValue = "Default file name: \(preview)"
    }

    private func loadOrCreateDocument(_ chosenURL: URL) {
        let fileName = MarkdownFilename.normalizedFilename(
            chosenURL.lastPathComponent,
            fallback: Self.suggestedFileName()
        ) ?? Self.suggestedFileName()
        let directoryURL = chosenURL.deletingLastPathComponent()
        rememberDocumentDirectory(directoryURL)
        documentFileName = fileName

        let suggestedDocumentURL = directoryURL.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: suggestedDocumentURL.path) {
            do {
                documentFileAccess.retainAccess(
                    to:
                    suggestedDocumentURL,
                    bookmarkKey: "boundMarkdownFileBookmark"
                )
                let text = try String(contentsOf: suggestedDocumentURL, encoding: .utf8)
                editorTextModel.setText(text)
                editorSurface.textView.undoManager?.removeAllActions()
                currentDocumentURL = suggestedDocumentURL
                statusLabel.stringValue =
                    "\(fileName) opened · Auto-saves every 30 seconds"
            } catch {
                presentFileError(
                    title: "Unable to Read Existing File",
                    message: error.localizedDescription
                )
                return
            }
        } else {
            editorTextModel.setText("")
            editorSurface.textView.undoManager?.removeAllActions()
            recoveryDraftStore.saveText("")
            do {
                try "".write(
                    to: suggestedDocumentURL,
                    atomically: true,
                    encoding: .utf8
                )
                documentFileAccess.retainAccess(
                    to:
                    suggestedDocumentURL,
                    bookmarkKey: "boundMarkdownFileBookmark"
                )
                currentDocumentURL = suggestedDocumentURL
                statusLabel.stringValue =
                    "\(fileName) created · Auto-saves every 30 seconds"
            } catch {
                currentDocumentURL = nil
                presentFileError(
                    title: "Unable to Create File",
                    message: error.localizedDescription
                )
                return
            }
        }

        refreshDocumentLocationLabel()
        window?.makeFirstResponder(editorSurface.textView)
    }

    @discardableResult
    func openStartupDocument(at fileURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return false
        }
        loadOrCreateDocument(fileURL)
        return true
    }

    func refreshAccessibilityPermissionStatus() {
        guard !isFocusSessionActive else {
            return
        }

        if FocusKeyboardBlocker.accessibilityAccessGranted {
            accessibilityPermissionButton.title = "Input Blocking Ready"
            accessibilityPermissionButton.isEnabled = false
        } else {
            accessibilityPermissionButton.title = "Configure Input Blocking"
            accessibilityPermissionButton.isEnabled = true
        }
    }

    private func buildUserInterface() {
        guard let contentView = window?.contentView else {
            return
        }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = EditorPalette.dark.background.cgColor

        let titleLabel = NSTextField(labelWithString: "Writing Jail")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        primaryTextLabels.append(titleLabel)

        accessibilityPermissionButton.bezelStyle = .inline
        accessibilityPermissionButton.controlSize = .small
        accessibilityPermissionButton.target = self
        accessibilityPermissionButton.action = #selector(configureAccessibilityPermission(_:))

        themeToggleButton.bezelStyle = .inline
        themeToggleButton.controlSize = .small
        themeToggleButton.target = self
        themeToggleButton.action = #selector(toggleTheme(_:))

        startFocusButton.title = "Start Focus"
        startFocusButton.bezelStyle = .rounded
        startFocusButton.controlSize = .large
        startFocusButton.keyEquivalent = "\r"
        startFocusButton.target = self
        startFocusButton.action = #selector(startFocusSession(_:))

        let topBar = NSStackView(
            views: [
                titleLabel,
                flexibleSpacer(),
                themeToggleButton,
                accessibilityPermissionButton,
                startFocusButton
            ]
        )
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 10

        documentLocationLabel.font = .systemFont(ofSize: 12)
        mutedTextLabels.append(documentLocationLabel)
        documentLocationLabel.lineBreakMode = .byTruncatingMiddle
        refreshDocumentLocationLabel()

        editorSurface = EditorSurfaceBuilder.make(
            editorTextModel: editorTextModel,
            palette: editorTextModel.palette
        )

        wordCountLabel.font = .systemFont(ofSize: 12)
        mutedTextLabels.append(wordCountLabel)

        statusLabel.font = .systemFont(ofSize: 12)
        mutedTextLabels.append(statusLabel)

        let shortcutLabel = NSTextField(
            labelWithString: "Cmd +/− Text Size · Standard editing shortcuts enabled"
        )
        shortcutLabel.font = .systemFont(ofSize: 12)
        mutedTextLabels.append(shortcutLabel)

        let footer = NSStackView(
            views: [wordCountLabel, flexibleSpacer(), statusLabel, shortcutLabel]
        )
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 14

        for view in [
            topBar,
            documentLocationLabel,
            editorSurface.scrollView,
            footer
        ] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            topBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            topBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            documentLocationLabel.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 14),
            documentLocationLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            documentLocationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            editorSurface.scrollView.topAnchor.constraint(equalTo: documentLocationLabel.bottomAnchor, constant: 10),
            editorSurface.scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            editorSurface.scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            editorSurface.scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),

            footer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            footer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
        ])

        refreshWordCount()
        themedContentView = contentView
        applyTheme()
        window?.makeFirstResponder(editorSurface.textView)
    }

    private func observeDocumentChanges() {
        NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification,
            object: editorTextModel.textStorage,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDocumentChange()
            }
        }
    }

    private func handleDocumentChange() {
        refreshWordCount()
        statusLabel.stringValue = "Modified · Auto-saves every 30 seconds"
    }

    private func refreshWordCount() {
        let text = editorTextModel.text
        let words = text.split(whereSeparator: \.isWhitespace).count
        wordCountLabel.stringValue = "\(words) words · \(text.count) characters"
    }

    private func scheduleAutoSaveTimer() {
        autoSaveTimer = Timer.scheduledTimer(
            withTimeInterval: 30,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.saveCurrentState()
            }
        }
        if let autoSaveTimer {
            RunLoop.main.add(autoSaveTimer, forMode: .common)
        }
    }

    private var suggestedDocumentURL: URL? {
        guard
            let documentDirectoryURL,
            let fileName = MarkdownFilename.normalizedFilename(
                documentFileName,
                fallback: Self.suggestedFileName()
            )
        else {
            return nil
        }
        return documentDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
    }

    func saveCurrentState() {
        recoveryDraftStore.saveText(editorTextModel.text)
        let saveURL = isFocusSessionActive ? suggestedDocumentURL : currentDocumentURL
        guard let saveURL else {
            statusLabel.stringValue = "Recovery draft saved · Select a file to start"
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: saveURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try editorTextModel.text.write(
                to: saveURL,
                atomically: true,
                encoding: .utf8
            )
            if documentFileAccess.activeResourceURL?.standardizedFileURL
                != saveURL.standardizedFileURL {
                documentFileAccess.retainAccess(
                    to:
                    saveURL,
                    bookmarkKey: "boundMarkdownFileBookmark"
                )
            }
            currentDocumentURL = saveURL
            statusLabel.stringValue = "Auto-saved · \(Self.currentTimeString())"
        } catch {
            statusLabel.stringValue = "Save failed: \(error.localizedDescription)"
        }
    }

    private func refreshDocumentLocationLabel() {
        if let suggestedDocumentURL {
            let isCurrentDocument = currentDocumentURL?.standardizedFileURL == suggestedDocumentURL.standardizedFileURL
            let exists = FileManager.default.fileExists(atPath: suggestedDocumentURL.path)
            let documentState: String
            if isCurrentDocument {
                documentState = "editing"
            } else if exists {
                documentState = "existing file · loaded on start"
            } else {
                documentState = "new file"
            }
            documentLocationLabel.stringValue =
                "Save file (\(documentState)): \(suggestedDocumentURL.lastPathComponent)"
            documentLocationLabel.toolTip = suggestedDocumentURL.path
        } else {
            documentLocationLabel.stringValue =
                "Choose a file or enter a file name before starting."
            documentLocationLabel.toolTip = nil
        }
    }

    private func restoreSecondaryDisplaySettings() {
        secondaryDisplayMode =
            UserDefaults.standard.string(forKey: "secondaryDisplayMode")
            .flatMap(SecondaryDisplayMode.init(rawValue:))
            ?? .systemWallpaper

        if let restoredImageURL = secondaryImageAccess.restoreAccess(
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

    func presentSecondaryDisplayDialog() {
        guard NSScreen.screens.count > 1 else {
            return
        }

        let displayModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for mode in SecondaryDisplayMode.allCases {
            displayModePopup.addItem(withTitle: mode.displayName)
        }
        displayModePopup.selectItem(
            at: SecondaryDisplayMode.allCases.firstIndex(
                of: secondaryDisplayMode
            ) ?? 1
        )
        let previousModeIndex = displayModePopup.indexOfSelectedItem

        let solidColorWell = NSColorWell()
        solidColorWell.color = secondaryColor

        let modeLabel = NSTextField(labelWithString: "Display content")
        let colorLabel = NSTextField(labelWithString: "Solid color")
        let instructionsLabel = NSTextField(
            wrappingLabelWithString:
                "This setting applies to every secondary display. Selecting Custom Image opens an image picker immediately."
        )
        instructionsLabel.textColor = .secondaryLabelColor
        var pendingCustomImageURL = secondaryImageURL

        let modeSelectionActionTarget = ClosureActionTarget {
            let index = displayModePopup.indexOfSelectedItem
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
                displayModePopup.selectItem(at: previousModeIndex)
                return
            }
            pendingCustomImageURL = imageURL
            instructionsLabel.stringValue = "Selected image: \(imageURL.lastPathComponent)"
        }
        displayModePopup.target = modeSelectionActionTarget
        displayModePopup.action = #selector(ClosureActionTarget.invoke(_:))

        let modeRow = NSStackView(views: [modeLabel, displayModePopup])
        modeRow.orientation = .horizontal
        modeRow.alignment = .centerY
        modeRow.spacing = 12

        let colorRow = NSStackView(views: [colorLabel, solidColorWell])
        colorRow.orientation = .horizontal
        colorRow.alignment = .centerY
        colorRow.spacing = 12

        let accessory = NSStackView(views: [modeRow, colorRow, instructionsLabel])
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
        let alertResponse = withExtendedLifetime(modeSelectionActionTarget) {
            alert.runModal()
        }
        guard alertResponse == .alertFirstButtonReturn else {
            return
        }

        let index = displayModePopup.indexOfSelectedItem
        guard SecondaryDisplayMode.allCases.indices.contains(index) else {
            return
        }
        let selectedDisplayMode = SecondaryDisplayMode.allCases[index]

        if selectedDisplayMode == .customImage {
            guard let imageURL = pendingCustomImageURL else {
                statusLabel.stringValue =
                    "Select an image before applying Custom Image."
                return
            }
            secondaryImageURL = imageURL
            secondaryImageAccess.retainAccess(
                to:
                imageURL,
                bookmarkKey: "secondaryDisplayImageBookmark"
            )
            UserDefaults.standard.set(
                imageURL.path,
                forKey: "secondaryDisplayImagePath"
            )
        } else if selectedDisplayMode == .solidColor {
            secondaryColor = solidColorWell.color
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

        secondaryDisplayMode = selectedDisplayMode
        UserDefaults.standard.set(
            selectedDisplayMode.rawValue,
            forKey: "secondaryDisplayMode"
        )
        statusLabel.stringValue =
            "Secondary display set to \(selectedDisplayMode.displayName)"
    }

    @objc private func presentOpenDocumentPanel(_ sender: Any?) {
        saveCurrentState()

        let panel = NSOpenPanel()
        panel.title = "Open Markdown File"
        panel.prompt = "Open"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText
        ]
        if let documentDirectoryURL {
            panel.directoryURL = documentDirectoryURL
        }

        guard panel.runModal() == .OK, let fileURL = panel.url else {
            return
        }

        do {
            documentFileAccess.retainAccess(
                to:
                fileURL,
                bookmarkKey: "boundMarkdownFileBookmark"
            )
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            editorTextModel.setText(text)
            editorSurface.textView.undoManager?.removeAllActions()
            rememberDocumentDirectory(fileURL.deletingLastPathComponent())
            currentDocumentURL = fileURL
            documentFileName = fileURL.lastPathComponent
            refreshDocumentLocationLabel()
            statusLabel.stringValue =
                "\(fileURL.lastPathComponent) opened · Auto-saves every 30 seconds"
            window?.makeFirstResponder(editorSurface.textView)
        } catch {
            presentFileError(
                title: "Unable to Open File",
                message: error.localizedDescription
            )
        }
    }

    @objc func openDocumentFromMenu(_ sender: Any?) {
        presentOpenDocumentPanel(sender)
    }

    private func resolveDocumentURLForFocus() -> URL? {
        if documentDirectoryURL != nil {
            guard let fileName = MarkdownFilename.normalizedFilename(
                documentFileName,
                fallback: Self.suggestedFileName()
            ) else {
                presentFileError(
                    title: "Check the File Name",
                    message: "File names cannot contain /. The file will be saved as .md."
                )
                return nil
            }
            documentFileName = fileName
            refreshDocumentLocationLabel()
            return documentDirectoryURL?.appendingPathComponent(fileName, isDirectory: false)
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

        rememberDocumentDirectory(chosenURL.deletingLastPathComponent())
        documentFileName = chosenURL.lastPathComponent
        refreshDocumentLocationLabel()
        return chosenURL
    }

    private func rememberDocumentDirectory(_ directoryURL: URL) {
        documentDirectoryURL = directoryURL
        UserDefaults.standard.set(
            directoryURL.path,
            forKey: "lastMarkdownFolder"
        )
    }

    private func prepareDocumentForFocus(_ suggestedDocumentURL: URL) -> Bool {
        let isSameFile =
            currentDocumentURL?.standardizedFileURL == suggestedDocumentURL.standardizedFileURL
        let fileExists = FileManager.default.fileExists(atPath: suggestedDocumentURL.path)
        if fileExists {
            documentFileAccess.retainAccess(
                to:
                suggestedDocumentURL,
                bookmarkKey: "boundMarkdownFileBookmark"
            )
        } else {
            documentFileAccess.retainAccess(
                to: suggestedDocumentURL.deletingLastPathComponent()
            )
        }

        if !isSameFile {
            saveCurrentState()
        }

        if fileExists && !isSameFile {
            do {
                let text = try String(contentsOf: suggestedDocumentURL, encoding: .utf8)
                editorTextModel.setText(text)
                editorSurface.textView.undoManager?.removeAllActions()
                currentDocumentURL = suggestedDocumentURL
                statusLabel.stringValue =
                    "\(suggestedDocumentURL.lastPathComponent) loaded from disk"
            } catch {
                presentFileError(
                    title: "Unable to Read Existing File",
                    message: "\(suggestedDocumentURL.path)\n\n\(error.localizedDescription)"
                )
                return false
            }
        } else {
            currentDocumentURL = suggestedDocumentURL
        }

        refreshDocumentLocationLabel()
        return true
    }

    private func presentFileError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func suggestedFileName() -> String {
        let template = UserDefaults.standard.string(
            forKey: defaultFilenameTemplateKey
        ) ?? DefaultFilenameTemplate.defaultTemplate
        return DefaultFilenameTemplate.makeFilename(
            template: template,
            date: Date()
        ) ?? DefaultFilenameTemplate.makeFilename(
            template: DefaultFilenameTemplate.defaultTemplate,
            date: Date()
        ) ?? "focus.md"
    }

    private static let defaultFilenameTemplateKey = "defaultFileNameFormat"

    private static func currentTimeString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    @objc private func startFocusSession(_ sender: Any?) {
        guard !isFocusSessionActive else {
            return
        }
        guard let duration = requestFocusSessionDuration() else {
            return
        }
        guard let suggestedDocumentURL = resolveDocumentURLForFocus() else {
            return
        }
        guard prepareDocumentForFocus(suggestedDocumentURL) else {
            return
        }

        if !FocusKeyboardBlocker.accessibilityAccessGranted {
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
                configureAccessibilityPermission(nil)
                return
            default:
                return
            }
        }

        beginFocusSession(duration: duration, suggestedDocumentURL: suggestedDocumentURL)
    }

    private func requestFocusSessionDuration() -> FocusSessionDuration? {
        while true {
            let durationLabel = NSTextField(labelWithString: "Duration (minutes)")
            let durationPopup = NSPopUpButton(
                frame: NSRect(x: 0, y: 0, width: 120, height: 26),
                pullsDown: false
            )
            for minutes in FocusSessionDuration.availableMinuteOptions {
                durationPopup.addItem(
                    withTitle: FocusSessionDuration.displayLabel(forMinutes: minutes)
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
                let duration = FocusSessionDuration(input: String(selectedMinutes)) else {
                continue
            }

            if duration.totalSeconds >= 30 * 60 {
                let confirmation = NSAlert()
                confirmation.messageText = "Confirm Long Focus Session"
                confirmation.informativeText =
                    "This session will last \(duration.wholeMinutes) minutes. You will not be able to leave Writing Jail until the timer ends."
                confirmation.addButton(withTitle: "Start Session")
                confirmation.addButton(withTitle: "Change Duration")
                if confirmation.runModal() != .alertFirstButtonReturn {
                    continue
                }
            }
            return duration
        }
    }

    private func beginFocusSession(duration: FocusSessionDuration, suggestedDocumentURL: URL) {
        saveCurrentState()
        isFocusSessionActive = true
        preFocusPresentationOptions = NSApp.presentationOptions

        let overlay = FocusSessionOverlayController(
            editorTextModel: editorTextModel,
            duration: duration.totalSeconds,
            documentFileName: suggestedDocumentURL.lastPathComponent,
            secondaryDisplayMode: secondaryDisplayMode,
            secondaryImageURL: secondaryImageURL,
            secondaryColor: secondaryColor
        ) { [weak self] in
            self?.endFocusSession(reason: .complete)
        }
        focusOverlayController = overlay
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

        keyboardBlocker.onEmergencyExit = { [weak self] in
            self?.endFocusSession(reason: .emergency)
        }
        if !keyboardBlocker.startBlocking() {
            statusLabel.stringValue = "System shortcut blocking could not start"
        } else {
            statusLabel.stringValue = "Maximum focus lock active"
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.orderOut(nil)
    }

    private func endFocusSession(reason: EndReason) {
        guard isFocusSessionActive else {
            return
        }

        keyboardBlocker.stopBlocking()
        keyboardBlocker.onEmergencyExit = nil
        NSApp.presentationOptions = preFocusPresentationOptions
        saveCurrentState()

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        focusOverlayController?.dismiss()
        focusOverlayController = nil
        isFocusSessionActive = false

        statusLabel.stringValue = reason == .complete
            ? "Focus complete · Saved"
            : "Emergency exit · Saved"
        applyTheme()
        refreshAccessibilityPermissionStatus()

        window?.makeFirstResponder(editorSurface.textView)
    }

    @objc private func configureAccessibilityPermission(_ sender: Any?) {
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            presentManualAccessibilityInstructions()
            return
        }
        FocusKeyboardBlocker.requestAccessibilityAccess()
        FocusKeyboardBlocker.openAccessibilityPrivacySettings()
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
        FocusKeyboardBlocker.openAccessibilityPrivacySettings()
    }

    func releaseSecurityScopedResources() {
        documentFileAccess.releaseAccess()
        secondaryImageAccess.releaseAccess()
    }

    private func flexibleSpacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

}
