import AppKit

private final class FocusWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class AmbientWindow: NSWindow {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

@MainActor
final class FocusOverlayController {
    private let document: EditorDocument
    private let deadline: Date
    private let destinationName: String
    private let secondaryMode: SecondaryDisplayMode
    private let secondaryImageURL: URL?
    private let secondaryColor: NSColor
    private let onComplete: () -> Void

    private var windows: [NSWindow] = []
    private var editorWindows: [NSWindow] = []
    private var editorDisplayID: CGDirectDisplayID?
    private var countdownLabels: [NSTextField] = []
    private var footerLabels: [NSTextField] = []
    private var countdownTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var isActive = false

    init(
        document: EditorDocument,
        duration: TimeInterval,
        destinationName: String,
        secondaryMode: SecondaryDisplayMode,
        secondaryImageURL: URL?,
        secondaryColor: NSColor,
        onComplete: @escaping () -> Void
    ) {
        self.document = document
        self.deadline = Date().addingTimeInterval(duration)
        self.destinationName = destinationName
        self.secondaryMode = secondaryMode
        self.secondaryImageURL = secondaryImageURL
        self.secondaryColor = secondaryColor
        self.onComplete = onComplete
    }

    func present() {
        isActive = true
        editorDisplayID = NSScreen.main.flatMap(displayID)
        rebuildWindows()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildWindows()
            }
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let activeApp = notification.userInfo?[
                    NSWorkspace.applicationUserInfoKey
                ] as? NSRunningApplication,
                activeApp.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else {
                return
            }
            Task { @MainActor in
                self?.returnToFront()
            }
        }

        countdownTimer = Timer.scheduledTimer(
            withTimeInterval: 0.25,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(countdownTimer!, forMode: .common)
        tick()
    }

    func dismiss() {
        isActive = false
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

        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        editorWindows.removeAll()
        countdownLabels.removeAll()
        footerLabels.removeAll()
    }

    private func tick() {
        guard isActive else {
            return
        }

        let remaining = max(0, deadline.timeIntervalSinceNow)
        let timeText = Self.format(remaining)
        let footerText = footerText()
        for label in countdownLabels {
            label.stringValue = timeText
        }
        for label in footerLabels {
            label.stringValue = footerText
        }

        if remaining <= 0 {
            isActive = false
            countdownTimer?.invalidate()
            countdownTimer = nil
            onComplete()
        }
    }

    private func rebuildWindows() {
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        editorWindows.removeAll()
        countdownLabels.removeAll()
        footerLabels.removeAll()

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
                secondaryMode == .mirrorEditor
                || displayID(for: screen) == editorDisplayID
            let window = isEditorScreen
                ? makeEditorWindow(for: screen)
                : makeAmbientWindow(for: screen)
            windows.append(window)
            window.orderFrontRegardless()

            if isEditorScreen {
                editorWindows.append(window)
            }
            if displayID(for: screen) == editorDisplayID {
                window.makeKey()
            }
        }

        returnToFront()
    }

    private func makeEditorWindow(for screen: NSScreen) -> NSWindow {
        let palette = document.palette
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
        let themeButton = NSButton(
            title: document.theme.switchButtonTitle,
            target: self,
            action: #selector(toggleTheme(_:))
        )
        themeButton.bezelStyle = .inline
        themeButton.controlSize = .small
        themeButton.contentTintColor = palette.accent

        let header = NSStackView(
            views: [
                title,
                divider,
                status,
                flexibleSpacer(),
                countdown,
                themeButton
            ]
        )
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12

        let surface = EditorSurfaceFactory.make(
            document: document,
            palette: palette
        )
        let footer = makeLabel(
            footerText(),
            font: .systemFont(ofSize: 12),
            color: palette.secondaryText
        )

        for view in [header, surface.scrollView, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),

            surface.scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            surface.scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            surface.scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            surface.scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -30),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18)
        ])

        countdownLabels.append(countdown)
        footerLabels.append(footer)
        window.initialFirstResponder = surface.textView
        window.makeFirstResponder(surface.textView)
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
        switch secondaryMode {
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
            window = FocusWindow(
                contentRect: NSRect(origin: .zero, size: screen.frame.size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
        } else {
            window = AmbientWindow(
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
        window.appearance = NSAppearance(named: document.theme.nsAppearance)
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
        document.setTheme(document.theme.toggled)
        rebuildWindows()
    }

    private func returnToFront() {
        guard isActive else {
            return
        }
        NSApp.activate(ignoringOtherApps: true)

        guard let window = editorWindows.first else {
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

    private static func format(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval.rounded(.up))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func footerText() -> String {
        let text = document.text
        let words = text.split(whereSeparator: \.isWhitespace).count
        return "\(destinationName) · \(words) words · \(text.count) characters · Auto-saves every 30 seconds"
    }
}
