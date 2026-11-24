import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Keeps an enabled switch visibly on even when its window is inactive.
struct SettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: ToggleStyleConfiguration) -> some View {
        SettingsSwitchBody(configuration: configuration)
    }
}

private struct SettingsSwitchBody: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            LabeledContent {
                // Let the native switch supply metrics for the current control size.
                // Opacity keeps it laid out; hidden() would use fallback metrics.
                Toggle("", isOn: .constant(configuration.isOn))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(controlSize)
                    .disabled(true)
                    .opacity(0)
                    .accessibilityHidden(true)
                    .overlay {
                        Capsule()
                            .fill(configuration.isOn ? onColor : SettingsStyle.switchOff)
                            .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                                Circle()
                                    .fill(.white)
                                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                                    .padding(2)
                            }
                            .opacity(isEnabled ? 1 : 0.5)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: configuration.isOn)
                    }
            } label: {
                configuration.label
            }
            .fixedSize()
        }
        .buttonStyle(SettingsSwitchButtonStyle())
        .focusable(isEnabled)
        .focusEffectDisabled()
        .onKeyPress(.space) {
            guard isEnabled else { return .ignored }
            configuration.isOn.toggle()
            return .handled
        }
        .accessibilityRepresentation {
            Toggle(configuration).toggleStyle(.switch)
        }
    }

    private var onColor: Color {
        activeState == .key ? SettingsStyle.switchOn : SettingsStyle.inactiveSwitchOn
    }
}

/// The switch supplies its own state feedback; pressing must not dim its label.
private struct SettingsSwitchButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .contentShape(Rectangle())
    }
}

struct SettingsPanel<Content: View>: View {
    let title: String
    let symbol: String?
    let contentPadding: EdgeInsets
    @ViewBuilder var content: Content
    init(_ title: String = "", symbol: String? = nil,
         contentPadding: EdgeInsets = SettingsStyle.panelInsets,
         @ViewBuilder content: () -> Content) {
        self.title = title; self.symbol = symbol; self.contentPadding = contentPadding; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsStyle.Spacing.groups) {
            if !title.isEmpty {
                HStack(spacing: SettingsStyle.Spacing.inline) {
                    if let symbol { Image(systemName: symbol).foregroundStyle(.secondary) }
                    Text(title).font(SettingsStyle.Typography.panelTitle)
                }
            }
            content
        }
        .padding(contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsStyle.subtle, in: RoundedRectangle(cornerRadius: SettingsStyle.panelRadius))
        .overlay { RoundedRectangle(cornerRadius: SettingsStyle.panelRadius).strokeBorder(Color.primary.opacity(0.07)) }
    }
}

struct SettingsStatus: View {
    let title: String
    var color: Color = .secondary
    var fixedWidth: CGFloat?

    init(title: String, color: Color = .secondary, fixedWidth: CGFloat? = nil) {
        self.title = title
        self.color = color
        self.fixedWidth = fixedWidth
    }

    var body: some View {
        label
            .foregroundStyle(color)
            .background(color.opacity(0.10), in: Capsule())
    }

    @ViewBuilder
    private var label: some View {
        if let fixedWidth {
            Text(title).font(SettingsStyle.Typography.caption.weight(.medium)).lineLimit(1)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .frame(width: fixedWidth)
        } else {
            Text(title).font(SettingsStyle.Typography.caption.weight(.medium))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .fixedSize()
        }
    }
}

struct SettingsPermissionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let granted: Bool
    let action: () -> Void

    init(_ title: String, detail: String, symbol: String, granted: Bool, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.granted = granted
        self.action = action
    }

    var body: some View {
        SettingsPreference(symbol: symbol, title: title, detail: detail) {
            HStack(spacing: SettingsStyle.Spacing.controls) {
                SettingsStatus(title: granted ? "已授权" : "待授权", color: granted ? .green : .orange)
                Button(granted ? "系统设置" : "前往授权", action: action)
                    .frame(width: 84)
                    .accessibilityLabel(granted ? "打开\(title)设置" : "授权\(title)")
            }
        }
    }
}

struct SettingsPreference<Control: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder var control: Control
    var body: some View {
        HStack(spacing: SettingsStyle.Spacing.controls) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.secondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                if !detail.isEmpty { Text(detail).font(SettingsStyle.Typography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 18)
            control
        }.padding(.vertical, 6)
    }
}

struct SettingsEmpty: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: SettingsStyle.Spacing.inline) {
            Image(systemName: symbol).font(.system(size: 32)).foregroundStyle(.tertiary).padding(.bottom, 5)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 35)
    }
}

func batterySymbol(for percent: Int) -> String {
    switch percent {
    case 88...: "battery.100percent"
    case 63...: "battery.75percent"
    case 38...: "battery.50percent"
    case 13...: "battery.25percent"
    default: "battery.0percent"
    }
}

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版本" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev" }
    static let repository = URL(string: "https://github.com/tokenzz-vip/JoyHarness")!
    static let website = URL(string: "https://joyharness.tokenzz.vip")!
}

