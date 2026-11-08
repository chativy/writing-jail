import AppKit

final class EditorTextModel {
    let textStorage = NSTextStorage()

    private(set) var fontSize: CGFloat
    private(set) var theme: EditorTheme
    private let registeredTextViews = NSHashTable<NSTextView>.weakObjects()
    private let bodyParagraphStyle: NSParagraphStyle

    init(text: String) {
        let storedFontSize = UserDefaults.standard.double(
            forKey: "editorFontSize"
        )
        fontSize = storedFontSize > 0 ? CGFloat(storedFontSize) : 20
        theme = .stored

        let mutableParagraphStyle = NSMutableParagraphStyle()
        mutableParagraphStyle.lineBreakMode = .byCharWrapping
        bodyParagraphStyle = mutableParagraphStyle

        textStorage.setAttributedString(
            NSAttributedString(
                string: text,
                attributes: [
                    .font: preferredFont,
                    .paragraphStyle: bodyParagraphStyle,
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
        applyAppearance(to: textView)
    }

    func changeFontSize(by delta: CGFloat) {
        let newFontSize = min(max(fontSize + delta, 12), 72)
        guard newFontSize != fontSize else {
            NSSound.beep()
            return
        }

        fontSize = newFontSize
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
            applyAppearance(to: textView)
            textView.needsLayout = true
            textView.needsDisplay = true
        }
    }

    private func applyAppearance(to textView: NSTextView) {
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
