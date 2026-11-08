import AppKit

private final class FocusEditorWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class AmbientOverlayWindow: NSWindow {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

@MainActor
final class FocusSessionOverlayController {
    private let editorTextModel: EditorTextModel
    private let sessionDeadline: Date
    private let documentFileName: String
    private let secondaryDisplayMode: SecondaryDisplayMode
    private let secondaryImageURL: URL?
    private let secondaryColor: NSColor
    private let completionHandler: () -> Void

    private var overlayWindows: [NSWindow] = []
    private var editorOverlayWindows: [NSWindow] = []
    private var editorDisplayID: CGDirectDisplayID?
    private var countdownTextLabels: [NSTextField] = []
    private var footerTextLabels: [NSTextField] = []
    private var countdownTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var isPresented = false

    init(
        editorTextModel: EditorTextModel,
        duration: TimeInterval,
        documentFileName: String,
        secondaryDisplayMode: SecondaryDisplayMode,
        secondaryImageURL: URL?,
        secondaryColor: NSColor,
        completionHandler: @escaping () -> Void
    ) {
        self.editorTextModel = editorTextModel
        self.sessionDeadline = Date().addingTimeInterval(duration)
        self.documentFileName = documentFileName
        self.secondaryDisplayMode = secondaryDisplayMode
        self.secondaryImageURL = secondaryImageURL
        self.secondaryColor = secondaryColor
        self.completionHandler = completionHandler
    }

    func present() {
        isPresented = true
        editorDisplayID = NSScreen.main.flatMap(displayID)
        rebuildOverlayWindows()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildOverlayWindows()
            }
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let activatedApplication = notification.userInfo?[
                    NSWorkspace.applicationUserInfoKey
                ] as? NSRunningApplication,
                activatedApplication.processIdentifier
                    != ProcessInfo.processInfo.processIdentifier
            else {
                return
            }
            Task { @MainActor in
                self?.activateEditorWindow()
            }
        }

        countdownTimer = Timer.scheduledTimer(
            withTimeInterval: 0.25,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateCountdown()
            }
        }
        RunLoop.main.add(countdownTimer!, forMode: .common)
        updateCountdown()
    }

    func dismiss() {
        isPresented = false
        countdownTimer?.invalidate()
        countdownTimer = nil

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        screenObserver = nil
        activationObserver = nil

        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
        editorOverlayWindows.removeAll()
        countdownTextLabels.removeAll()
        footerTextLabels.removeAll()
    }

    private func updateCountdown() {
        guard isPresented else {
            return
        }

        let remaining = max(0, sessionDeadline.timeIntervalSinceNow)
        let timeText = Self.formattedCountdown(remaining)
        let footerMessage = makeFooterMessage()
        for label in countdownTextLabels {
            label.stringValue = timeText
        }
        for label in footerTextLabels {
            label.stringValue = footerMessage
        }

        if remaining <= 0 {
            isPresented = false
            countdownTimer?.invalidate()
            countdownTimer = nil
            completionHandler()
        }
    }

    private func rebuildOverlayWindows() {
        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
        editorOverlayWindows.removeAll()
        countdownTextLabels.removeAll()
        footerTextLabels.removeAll()

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return
        }

        let retainedEditorDisplayID = editorDisplayID
        let editorStillConnected = retainedEditorDisplayID.map { displayID in
            screens.contains { self.displayID(for: $0) == displayID }
        } ?? false
        if !editorStillConnected {
            editorDisplayID = NSScreen.main.flatMap(displayID)
                ?? screens.first.flatMap(displayID)
        }

        for screen in screens {
            let isEditorScreen =
                secondaryDisplayMode == .mirrorEditor
                || displayID(for: screen) == editorDisplayID
            let window = isEditorScreen
                ? makeEditorWindow(for: screen)
                : makeAmbientWindow(for: screen)
            overlayWindows.append(window)
            window.orderFrontRegardless()

            if isEditorScreen {
                editorOverlayWindows.append(window)
            }
            if displayID(for: screen) == editorDisplayID {
                window.makeKey()
            }
        }

        activateEditorWindow()
    }

    private func makeEditorWindow(for screen: NSScreen) -> NSWindow {
        let palette = editorTextModel.palette
        let window = makeOverlayWindow(
            for: screen,
            canBecomeKey: true,
            palette: palette
        )
        let root = makeRootView(for: screen, palette: palette)
        window.contentView = root

        let title = makeLabel(
            "WRITING JAIL",
            font: .monospacedSystemFont(ofSize: 15, weight: .bold),
            color: palette.accent
        )
        let divider = makeLabel(
            "•",
            font: .systemFont(ofSize: 14),
            color: palette.secondaryText
        )
        let status = makeLabel(
            "FOCUSING",
            font: .systemFont(ofSize: 14, weight: .medium),
            color: palette.secondaryText
        )
        let countdown = makeLabel(
            "00:00:00",
            font: .monospacedDigitSystemFont(ofSize: 24, weight: .semibold),
            color: palette.foreground
        )
        let themeToggleButton = NSButton(
            title: editorTextModel.theme.toggleButtonTitle,
            target: self,
            action: #selector(toggleTheme(_:))
        )
        themeToggleButton.bezelStyle = .inline
        themeToggleButton.controlSize = .small
        themeToggleButton.contentTintColor = palette.accent

        let header = NSStackView(
            views: [
                title,
                divider,
                status,
                flexibleSpacer(),
                countdown,
                themeToggleButton
            ]
        )
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12

        let editorSurface = EditorSurfaceBuilder.make(
            editorTextModel: editorTextModel,
            palette: palette
        )
        let footer = makeLabel(
            makeFooterMessage(),
            font: .systemFont(ofSize: 12),
            color: palette.secondaryText
        )

        for view in [header, editorSurface.scrollView, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),

            editorSurface.scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            editorSurface.scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            editorSurface.scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            editorSurface.scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -30),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18)
        ])

        countdownTextLabels.append(countdown)
        footerTextLabels.append(footer)
        window.initialFirstResponder = editorSurface.textView
        window.makeFirstResponder(editorSurface.textView)
        return window
    }

    private func makeAmbientWindow(for screen: NSScreen) -> NSWindow {
        let window = makeOverlayWindow(
            for: screen,
            canBecomeKey: false,
            palette: .dark
        )
        let root = makeRootView(for: screen, palette: .dark)
        window.contentView = root

        let image: NSImage?
        switch secondaryDisplayMode {
        case .systemWallpaper:
            image = NSWorkspace.shared
                .desktopImageURL(for: screen)
                .flatMap(NSImage.init(contentsOf:))
        case .customImage:
            image = secondaryImageURL
                .flatMap(NSImage.init(contentsOf:))
                ?? NSWorkspace.shared
                    .desktopImageURL(for: screen)
                    .flatMap(NSImage.init(contentsOf:))
        case .solidColor, .mirrorEditor:
            image = nil
        }

        if let image {
            let imageView = NSImageView()
            imageView.image = image
            imageView.imageAlignment = .alignCenter
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: root.topAnchor),
                imageView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
            ])
        } else {
            root.layer?.backgroundColor = secondaryColor.cgColor
        }

        return window
    }

    private func makeOverlayWindow(
        for screen: NSScreen,
        canBecomeKey: Bool,
        palette: EditorPalette
    ) -> NSWindow {
        let window: NSWindow
        if canBecomeKey {
            window = FocusEditorWindow(
                contentRect: NSRect(origin: .zero, size: screen.frame.size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
        } else {
            window = AmbientOverlayWindow(
                contentRect: NSRect(origin: .zero, size: screen.frame.size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
        }
        window.setFrame(screen.frame, display: true)
        window.level = .screenSaver
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        window.isReleasedWhenClosed = false
        window.isMovable = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = canBecomeKey
        window.hasShadow = false
        window.animationBehavior = .none
        window.backgroundColor = palette.background
        window.appearance = NSAppearance(
            named: editorTextModel.theme.systemAppearance
        )
        return window
    }

    private func makeRootView(
        for screen: NSScreen,
        palette: EditorPalette
    ) -> NSView {
        let root = NSView()
        root.frame = NSRect(origin: .zero, size: screen.frame.size)
        root.autoresizingMask = [.width, .height]
        root.wantsLayer = true
        root.layer?.backgroundColor = palette.background.cgColor
        return root
    }

    @objc private func toggleTheme(_ sender: Any?) {
        editorTextModel.applyTheme(editorTextModel.theme.opposite)
        rebuildOverlayWindows()
    }

    private func activateEditorWindow() {
        guard isPresented else {
            return
        }
        NSApp.activate(ignoringOtherApps: true)

        guard let window = editorOverlayWindows.first else {
            return
        }
        window.makeKeyAndOrderFront(nil)
        if let firstResponder = window.initialFirstResponder {
            window.makeFirstResponder(firstResponder)
        }
    }

    private func makeLabel(
        _ text: String,
        font: NSFont,
        color: NSColor
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        return label
    }

    private func flexibleSpacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber)?.uint32Value
    }

    private static func formattedCountdown(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval.rounded(.up))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func makeFooterMessage() -> String {
        let text = editorTextModel.text
        let words = text.split(whereSeparator: \.isWhitespace).count
        return "\(documentFileName) · \(words) words · \(text.count) characters · Auto-saves every 30 seconds"
    }
}
