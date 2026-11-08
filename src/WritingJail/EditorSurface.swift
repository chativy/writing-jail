import AppKit

final class EditorTextView: NSTextView, NSTextViewDelegate {
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
        maintainBottomScrollMargin()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        maintainBottomScrollMargin()
    }

    func textDidChange(_ notification: Notification) {
        maintainBottomScrollMargin()
    }

    func maintainBottomScrollMargin() {
        guard let layoutManager, let textContainer else {
            return
        }
        layoutManager.ensureLayout(for: textContainer)

        let lineHeight = layoutManager.defaultLineHeight(
            for: font ?? NSFont.monospacedSystemFont(ofSize: 20, weight: .regular)
        )
        let bottomComfortMargin = lineHeight * bottomComfortLineCount
        let minimumEditorHeight =
            layoutManager.usedRect(for: textContainer).maxY
            + textContainerInset.height * 2
            + bottomComfortMargin
        if frame.height < minimumEditorHeight && !isUpdatingFrame {
            isUpdatingFrame = true
            super.setFrameSize(
                NSSize(width: frame.width, height: minimumEditorHeight)
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

        let selectionLineBottom: CGFloat
        if layoutManager.numberOfGlyphs > 0 {
            selectionLineBottom = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil
            ).maxY + textContainerInset.height
        } else {
            selectionLineBottom = textContainerInset.height + lineHeight
        }

        let desiredScrollY =
            selectionLineBottom + bottomComfortMargin - visibleRect.height
        let maximumScrollY = max(0, frame.height - visibleRect.height)
        let targetScrollY = min(max(0, desiredScrollY), maximumScrollY)
        if targetScrollY > visibleRect.minY + 0.5,
            let scrollView = enclosingScrollView {
            scrollView.contentView.scroll(
                to: NSPoint(x: visibleRect.minX, y: targetScrollY)
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

        let viewportWidth = max(1, contentSize.width)
        textView.minSize = NSSize(
            width: viewportWidth,
            height: contentSize.height
        )
        textView.maxSize = NSSize(
            width: viewportWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        if abs(textView.frame.width - viewportWidth) > 0.5 {
            var frame = textView.frame
            frame.size.width = viewportWidth
            frame.size.height = max(frame.height, contentSize.height)
            textView.frame = frame
        }

        let textContainerWidth = max(
            1,
            viewportWidth - textView.textContainerInset.width * 2
        )
        if let textContainer = textView.textContainer,
            abs(textContainer.containerSize.width - textContainerWidth) > 0.5 {
            textContainer.containerSize = NSSize(
                width: textContainerWidth,
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
