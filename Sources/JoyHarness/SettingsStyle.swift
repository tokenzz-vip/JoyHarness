import SwiftUI

/// Shared semantic styles for settings pages and their custom editors.
/// Native control metrics, artwork calibration and scaled diagrams own their geometry;
/// these values describe repeated layout roles, not a mandatory grid for every number.
enum SettingsStyle {
    static let sidebarWidth: CGFloat = 108
    static let pageHeaderHeight: CGFloat = 76
    static let pagePadding: CGFloat = 20
    static let panelPadding: CGFloat = 16
    static let controlPadding: CGFloat = 12
    static let compactControlPadding: CGFloat = 8
    static let panelRadius: CGFloat = 10
    static let controlRadius: CGFloat = 6
    static let panelInsets = EdgeInsets(top: panelPadding, leading: panelPadding,
                                       bottom: panelPadding, trailing: panelPadding)

    /// Gaps between related elements, control groups, panels and page sections.
    enum Spacing {
        static let inline: CGFloat = 8
        static let controls: CGFloat = 12
        static let groups: CGFloat = 16
        static let sections: CGFloat = 24
    }

    enum Typography {
        static let pageTitle = Font.system(size: 20, weight: .semibold)
        static let panelTitle = Font.system(size: 15, weight: .semibold)
        static let dialogTitle = Font.system(size: 18, weight: .semibold)
        static let bodySize: CGFloat = 13
        static let body = Font.system(size: bodySize)
        static let listTitle = body.weight(.medium)
        static let caption = Font.system(size: 11)
    }

    static let pageBackground = Color(nsColor: .controlBackgroundColor)
    static let panelBackground = Color.primary.opacity(0.022)
    static let buttonBackground = Color.primary.opacity(0.06)
    static let workspaceDivider = Color.primary.opacity(0.10)
    static let libraryWidth: CGFloat = 252
    static let subtle = Color.primary.opacity(0.035)
    static func shortcutPopoverBackground(in colorScheme: ColorScheme) -> Color {
        Color(white: colorScheme == .dark ? 0.11 : 0.99)
    }
    static let switchOff = Color.primary.opacity(0.16)
    static func phrasePadKeyBackground(in colorScheme: ColorScheme) -> Color {
        Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.115)
    }
    static func mappingTriggerLabel(in colorScheme: ColorScheme) -> Color {
        Color(white: colorScheme == .dark ? 0.72 : 89.0 / 255)
    }
    /// The window and the narrow preview enforce the same minimum content size.
    static let minimumWindowSize = CGSize(width: 1020, height: 772)
}

