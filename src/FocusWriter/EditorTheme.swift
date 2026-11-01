import AppKit

enum EditorTheme: String {
    case dark
    case ivory

    static var saved: EditorTheme {
        UserDefaults.standard.string(forKey: "editorTheme")
            .flatMap(EditorTheme.init(rawValue:))
            ?? .dark
    }

    var palette: EditorPalette {
        switch self {
        case .dark:
            return .dark
        case .ivory:
            return .ivory
        }
    }

    var switchButtonTitle: String {
        switch self {
        case .dark:
            return "Ivory Mode"
        case .ivory:
            return "Dark Mode"
        }
    }

    var nsAppearance: NSAppearance.Name {
        switch self {
        case .dark:
            return .darkAqua
        case .ivory:
            return .aqua
        }
    }

    var toggled: EditorTheme {
        self == .dark ? .ivory : .dark
    }
}
