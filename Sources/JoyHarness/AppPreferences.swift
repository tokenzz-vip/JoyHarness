import AppKit
import SwiftUI

enum AppThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { switch self { case .system: "跟随系统"; case .light: "浅色"; case .dark: "深色" } }
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum AppColorMode: String, CaseIterable, Identifiable {
    case iris, cobalt, plum, teal, raspberry, caramel, electricPurple, safari

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iris: "鸢尾紫"
        case .cobalt: "钴蓝"
        case .plum: "梅子紫"
        case .teal: "湖蓝绿"
        case .raspberry: "覆盆子红"
        case .caramel: "焦糖橙"
        case .electricPurple: "电光紫"
        case .safari: "指南针蓝"
        }
    }

    var palette: AppColorPalette {
        switch self {
        case .iris: .init(action: 0x6044D4, lightFill: 0xF0ECFF, darkFill: 0x302746, darkInk: 0xC9BFFF)
        case .cobalt: .init(action: 0x2859CC, lightFill: 0xEDF4FF, darkFill: 0x253655, darkInk: 0xAFC8FF)
        case .plum: .init(action: 0x7B389D, lightFill: 0xFAEDFA, darkFill: 0x3A2943, darkInk: 0xE7B7F4)
        case .teal: .init(action: 0x007680, lightFill: 0xE5F6F5, darkFill: 0x203C3F, darkInk: 0x8DDFD9)
        case .raspberry: .init(action: 0xAC285E, lightFill: 0xFDECF3, darkFill: 0x442738, darkInk: 0xF3AFCA)
        case .caramel: .init(action: 0xA34A1F, lightFill: 0xFFF1E7, darkFill: 0x442F25, darkInk: 0xFFC2A0)
        case .electricPurple: .init(action: 0x6D28D9, lightFill: 0xF4EDFF, darkFill: 0x34264B, darkInk: 0xD3B7FF)
        case .safari:
            .init(action: 0x0066CC, lightFill: 0xEAF6FF, darkFill: 0x17364D, darkInk: 0x8DD1FF,
                  sidebarColors: (light: 0xF5F7FA, dark: 0x222A34),
                  destructiveColors: (light: 0xC82E2E, dark: 0xFF7777))
        }
    }
}

struct AppColorPalette {
    let action: UInt32
    let lightFill: UInt32
    let darkFill: UInt32
    let darkInk: UInt32
    var sidebarColors: (light: UInt32, dark: UInt32)? = nil
    var destructiveColors: (light: UInt32, dark: UInt32)? = nil

    var actionTint: Color { Color(nsColor: Self.rgb(action)) }
    var selectionTint: Color { Color(nsColor: selectionInk) }
    var selectionBackground: Color { Color(nsColor: selectionFill) }
    var selectionInk: NSColor { Self.adaptive(light: action, dark: darkInk) }
    var selectionFill: NSColor { Self.adaptive(light: lightFill, dark: darkFill) }

    var sidebarBackground: Color? {
        sidebarColors.map { Color(nsColor: Self.adaptive(light: $0.light, dark: $0.dark)) }
    }

    var destructiveTint: Color {
        destructiveColors.map { Color(nsColor: Self.adaptive(light: $0.light, dark: $0.dark)) } ?? .red
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> NSColor {
        let lightColor = rgb(light)
        let darkColor = rgb(dark)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor
        }
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

extension EnvironmentValues {
    @Entry var appColorMode: AppColorMode = .iris
}
