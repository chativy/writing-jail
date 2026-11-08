import AppKit

enum EditorTheme: String {
    case dark
    case ivory

    static var stored: EditorTheme {
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

    var toggleButtonTitle: String {
        switch self {
        case .dark:
            return "Ivory Mode"
        case .ivory:
            return "Dark Mode"
        }
    }

    var systemAppearance: NSAppearance.Name {
        switch self {
        case .dark:
            return .darkAqua
        case .ivory:
            return .aqua
        }
    }

    var opposite: EditorTheme {
        self == .dark ? .ivory : .dark
    }
}
