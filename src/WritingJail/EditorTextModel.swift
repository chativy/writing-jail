import AppKit

final class EditorTextModel {
    let textStorage = NSTextStorage()

    private(set) var fontSize: CGFloat
    private(set) var theme: EditorTheme
    private let registeredTextViews = NSHashTable<NSTextView>.weakObjects()
    private let bodyParagraphStyle: NSParagraphStyle

    init(text: String) {
        let savedSize = UserDefaults.standard.double(forKey: "editorFontSize")
        fontSize = savedSize > 0 ? CGFloat(savedSize) : 20
        theme = .stored

        let bodyParagraphStyle = NSMutableParagraphStyle()
        bodyParagraphStyle.lineBreakMode = .byCharWrapping
        self.bodyParagraphStyle = bodyParagraphStyle

        textStorage.setAttributedString(
            NSAttributedString(
                string: text,
                attributes: [
                    .font: preferredFont,
                    .paragraphStyle: self.bodyParagraphStyle,
                    .foregroundColor: theme.palette.foreground
                ]
            )
        )
    }

    var preferredFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    var palette: EditorPalette {
        theme.palette
    }

    var text: String {
        textStorage.string
    }

    func registerTextView(_ textView: NSTextView) {
        registeredTextViews.add(textView)
        textView.typingAttributes[.font] = preferredFont
        textView.typingAttributes[.paragraphStyle] = bodyParagraphStyle
        textView.defaultParagraphStyle = bodyParagraphStyle
        textView.font = preferredFont
        applyAppearance(of: textView)
    }

    func changeFontSize(by delta: CGFloat) {
        let nextSize = min(max(fontSize + delta, 12), 72)
        guard nextSize != fontSize else {
            NSSound.beep()
            return
        }

        fontSize = nextSize
        UserDefaults.standard.set(Double(fontSize), forKey: "editorFontSize")

        if textStorage.length > 0 {
            textStorage.addAttribute(
                .font,
                value: preferredFont,
                range: NSRange(location: 0, length: textStorage.length)
            )
        }

        for textView in registeredTextViews.allObjects {
            textView.typingAttributes[.font] = preferredFont
            textView.typingAttributes[.paragraphStyle] = bodyParagraphStyle
            textView.font = preferredFont
            (textView as? EditorTextView)?.maintainBottomScrollMargin()
        }
    }

    func setText(_ text: String) {
        textStorage.setAttributedString(
            NSAttributedString(
                string: text,
                attributes: [
                    .font: preferredFont,
                    .paragraphStyle: bodyParagraphStyle,
                    .foregroundColor: palette.foreground
                ]
            )
        )
    }

    func applyTheme(_ theme: EditorTheme) {
        guard self.theme != theme else {
            return
        }
        self.theme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "editorTheme")
        if textStorage.length > 0 {
            textStorage.addAttribute(
                .foregroundColor,
                value: palette.foreground,
                range: NSRange(location: 0, length: textStorage.length)
            )
        }

        for textView in registeredTextViews.allObjects {
            applyAppearance(of: textView)
            textView.needsLayout = true
            textView.needsDisplay = true
        }
    }

    private func applyAppearance(of textView: NSTextView) {
        textView.appearance = NSAppearance(named: theme.systemAppearance)
        textView.backgroundColor = palette.background
        textView.textColor = palette.foreground
        textView.insertionPointColor = palette.accent
        textView.typingAttributes[.foregroundColor] = palette.foreground
        if let scrollView = textView.enclosingScrollView {
            scrollView.backgroundColor = palette.background
            scrollView.contentView.backgroundColor = palette.background
        }
    }
}

private final class EditorTextView: NSTextView, NSTextViewDelegate {
    private let bottomComfortLineCount: CGFloat = 4
    private var isUpdatingFrame = false

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let textContainer else {
            return
        }
        textContainer.containerSize = NSSize(
            width: max(0, newSize.width - textContainerInset.width * 2),
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        ensureBottomMargin()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        ensureBottomMargin()
    }

    func textDidChange(_ notification: Notification) {
        ensureBottomMargin()
    }

    func maintainBottomScrollMargin() {
        ensureBottomMargin()
    }

    private func ensureBottomMargin() {
        guard let layoutManager, let textContainer else {
            return
        }
        layoutManager.ensureLayout(for: textContainer)

        let lineHeight = layoutManager.defaultLineHeight(
            for: font ?? NSFont.monospacedSystemFont(ofSize: 20, weight: .regular)
        )
        let bottomMargin = lineHeight * bottomComfortLineCount
        let minimumHeight =
            layoutManager.usedRect(for: textContainer).maxY
            + textContainerInset.height * 2
            + bottomMargin
        if frame.height < minimumHeight && !isUpdatingFrame {
            isUpdatingFrame = true
            super.setFrameSize(
                NSSize(width: frame.width, height: minimumHeight)
            )
            isUpdatingFrame = false
        }

        let selectionLocation = selectedRange().location
        let characterLocation = min(
            max(0, selectionLocation),
            max(0, (textStorage?.length ?? 0) - 1)
        )
        let glyphIndex: Int
        if layoutManager.numberOfGlyphs > 0 {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: characterLocation, length: 0),
                actualCharacterRange: nil
            )
            glyphIndex = min(glyphRange.location, layoutManager.numberOfGlyphs - 1)
        } else {
            glyphIndex = 0
        }

        let lineBottom: CGFloat
        if layoutManager.numberOfGlyphs > 0 {
            lineBottom = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil
            ).maxY + textContainerInset.height
        } else {
            lineBottom = textContainerInset.height + lineHeight
        }

        let desiredTop = lineBottom + bottomMargin - visibleRect.height
        let maximumTop = max(0, frame.height - visibleRect.height)
        let targetTop = min(max(0, desiredTop), maximumTop)
        if targetTop > visibleRect.minY + 0.5,
            let scrollView = enclosingScrollView {
            scrollView.contentView.scroll(
                to: NSPoint(x: visibleRect.minX, y: targetTop)
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

private final class EditorScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let textView = documentView as? NSTextView else {
            return
        }

        let availableWidth = max(1, contentSize.width)
        textView.minSize = NSSize(
            width: availableWidth,
            height: contentSize.height
        )
        textView.maxSize = NSSize(
            width: availableWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        if abs(textView.frame.width - availableWidth) > 0.5 {
            var frame = textView.frame
            frame.size.width = availableWidth
            frame.size.height = max(frame.height, contentSize.height)
            textView.frame = frame
        }

        let wrappingWidth = max(
            1,
            availableWidth - textView.textContainerInset.width * 2
        )
        if let textContainer = textView.textContainer,
            abs(textContainer.containerSize.width - wrappingWidth) > 0.5 {
            textContainer.containerSize = NSSize(
                width: wrappingWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }
}

struct EditorSurface {
    let scrollView: NSScrollView
    let textView: NSTextView
}

enum EditorSurfaceBuilder {
    static func make(
        editorTextModel: EditorTextModel,
        palette: EditorPalette
    ) -> EditorSurface {
        let layoutManager = NSLayoutManager()
        editorTextModel.textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 900, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let textView = EditorTextView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 600),
            textContainer: textContainer
        )
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = palette.background
        textView.textColor = palette.foreground
        textView.insertionPointColor = palette.accent
        textView.textContainerInset = NSSize(width: 32, height: 28)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false

        let scrollView = EditorScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = palette.background
        scrollView.borderType = .noBorder
        scrollView.contentView.drawsBackground = true
        scrollView.contentView.backgroundColor = palette.background

        textView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: 900, height: 600)
        )
        textContainer.containerSize = NSSize(
            width: max(0, textView.frame.width - textView.textContainerInset.width * 2),
            height: CGFloat.greatestFiniteMagnitude
        )

        editorTextModel.registerTextView(textView)
        return EditorSurface(scrollView: scrollView, textView: textView)
    }
}

struct EditorPalette {
    let background: NSColor
    let foreground: NSColor
    let secondaryText: NSColor
    let accent: NSColor

    static let dark = EditorPalette(
        background: NSColor(calibratedWhite: 0.10, alpha: 1),
        foreground: NSColor(calibratedWhite: 0.94, alpha: 1),
        secondaryText: NSColor(calibratedWhite: 0.62, alpha: 1),
        accent: NSColor.systemTeal
    )

    static let ivory = EditorPalette(
        background: NSColor(
            calibratedRed: 0.96,
            green: 0.93,
            blue: 0.84,
            alpha: 1
        ),
        foreground: NSColor(
            calibratedRed: 0.10,
            green: 0.12,
            blue: 0.15,
            alpha: 1
        ),
        secondaryText: NSColor(
            calibratedRed: 0.40,
            green: 0.36,
            blue: 0.29,
            alpha: 1
        ),
        accent: NSColor(
            calibratedRed: 0.78,
            green: 0.30,
            blue: 0.18,
            alpha: 1
        )
    )

    static let main = dark
}
