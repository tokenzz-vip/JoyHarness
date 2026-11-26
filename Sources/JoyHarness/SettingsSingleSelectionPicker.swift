import SwiftUI

struct SettingsSelectionOption<Value: Hashable> {
    let value: Value
    let title: String
    var swatch: Color? = nil
}

/// A single choice list using the same below-field popover as the tag filter.
@MainActor
struct SettingsSingleSelectionPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [SettingsSelectionOption<Value>]
    let accessibilityLabel: String
    let identifier: String
    var missingSelectionTitle = "未选择"

    var body: some View {
        let selected = options.first { $0.value == selection }
        let title = selected?.title ?? missingSelectionTitle
        SettingsSelectionPopover(title: title, accessibilityLabel: accessibilityLabel, identifier: identifier) {
            HStack(spacing: SettingsStyle.Spacing.inline) {
                if let swatch = selected?.swatch { SettingsColorSwatch(color: swatch) }
                Text(title)
            }
        } content: { height, dismiss in
            SettingsSingleSelectionMenu(selection: $selection, options: options,
                                        maximumHeight: height, dismiss: dismiss)
        }
    }
}

@MainActor
private struct SettingsSingleSelectionMenu<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [SettingsSelectionOption<Value>]
    let maximumHeight: CGFloat
    let dismiss: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(options, id: \.value) { option in
                        SettingsSelectionRow(title: option.title, selected: option.value == selection, swatch: option.swatch) {
                            if selection != option.value { selection = option.value }
                            dismiss()
                        }
                        .id(option.value)
                    }
                }
                .padding(4)
            }
            .frame(height: min(maximumHeight, CGFloat(options.count) * 28 + 8))
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
    }
}

struct SettingsColorSwatch: View {
    let color: Color

    var body: some View {
        Circle().fill(color)
            .frame(width: 12, height: 12)
            .overlay { Circle().strokeBorder(.white.opacity(0.35)) }
            .accessibilityHidden(true)
    }
}
