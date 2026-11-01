import AppKit

enum SecondaryDisplayMode: String, CaseIterable {
    case mirrorEditor
    case systemWallpaper
    case customImage
    case solidColor

    var title: String {
        switch self {
        case .mirrorEditor:
            return "Mirror Editor"
        case .systemWallpaper:
            return "System Wallpaper"
        case .customImage:
            return "Custom Image"
        case .solidColor:
            return "Solid Color"
        }
    }
}
