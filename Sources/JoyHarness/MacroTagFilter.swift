import SwiftUI

@MainActor
struct MacroTagFilter: View {
    @Binding var selection: Set<String>
    let tags: [MacroTag]
    var isAssignment = false

    private var names: [String] {
        tags.filter { selection.contains($0.id) }.map(\.name)
    }

    private var emptyTitle: String { isAssignment ? "选择标签…" : "全部标签" }

    var body: some View {
        SettingsSelectionPopover(title: emptyTitle,
            accessibilityLabel: isAssignment ? "选择动作标签" : "按标签筛选组合动作",
            identifier: isAssignment ? "macro-tag-assignment" : "macro-tag-filter",
            accessibilityValue: names.isEmpty ? (isAssignment ? "无标签" : emptyTitle) : names.joined(separator: "、"),
            accessibilityHelp: "可选择多个标签，再次点击可取消",
            label: { MacroTagSelectionLabel(names: names, emptyTitle: emptyTitle) }) { height, _ in
            MacroTagFilterMenu(selection: $selection, tags: tags, showsAll: !isAssignment, maximumHeight: height)
        }
    }
}

@MainActor
private struct MacroTagSelectionLabel: View {
    let names: [String]
    let emptyTitle: String

    var body: some View {
        if names.isEmpty {
            Text(emptyTitle)
        } else {
            ViewThatFits(in: .horizontal) {
                ForEach((1...min(names.count, 12)).reversed(), id: \.self) { count in
                    HStack(spacing: 4) {
                        ForEach(names.prefix(count), id: \.self) { name in
                            tag(name)
                        }
                        if count < names.count { tag("+\(names.count - count)") }
                    }
                    .fixedSize()
                }
                tag("+\(names.count)")
            }
        }
    }

    private func tag(_ title: String) -> some View {
        Text(title)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.primary.opacity(0.12))
            }
    }
}

@MainActor
private struct MacroTagFilterMenu: View {
    @Binding var selection: Set<String>
    let tags: [MacroTag]
    let showsAll: Bool
    let maximumHeight: CGFloat

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if showsAll {
                    SettingsSelectionRow(title: "全部标签", selected: selection.isEmpty) { selection.removeAll() }
                    Divider().padding(.horizontal, SettingsStyle.Spacing.inline).padding(.vertical, 4)
                }
                ForEach(tags) { tag in
                    SettingsSelectionRow(title: tag.name, selected: selection.contains(tag.id)) {
                        if selection.contains(tag.id) { selection.remove(tag.id) }
                        else { selection.insert(tag.id) }
                    }
                }
            }
            .padding(4)
        }
        .frame(height: min(maximumHeight, CGFloat(tags.count) * 28 + (showsAll ? 45 : 8)))
    }
}
