import AppKit
import SwiftUI

@MainActor
final class ShortcutReferenceController {
    static let defaultSize = NSSize(width: 1000, height: 650)
    static let minimumSize = NSSize(width: 900, height: 600)
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible == true }
    var renderView: NSView? { panel?.contentView }

    func toggle(model: DashboardModel) {
        if isVisible { dismiss() }
        else { show(model: model, size: Self.defaultSize) }
    }

    func dismiss() { panel?.orderOut(nil) }

    func show(model: DashboardModel, size: NSSize) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let available = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let width = min(size.width, available.width)
        let height = min(size.height, available.height)
        let panel = panel ?? makePanel(model: model)
        self.panel = panel
        panel.setFrame(NSRect(x: available.midX - width / 2, y: available.midY - height / 2,
                              width: width, height: height), display: true)
        // Leave keyboard focus with the app whose mappings are displayed.
        panel.orderFrontRegardless()
    }

    private func makePanel(model: DashboardModel) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = RemoteAction.toggleShortcutReference.label
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let view = NSHostingView(rootView: ShortcutReferenceView(model: model, close: { [weak self] in self?.dismiss() }))
        view.sizingOptions = []
        panel.contentView = view
        return panel
    }
}

@MainActor
private struct ShortcutReferenceView: View {
    @ObservedObject var model: DashboardModel
    let close: () -> Void
    private let minimumDiagramHeight: CGFloat = 530

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: SettingsStyle.Spacing.controls) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(RemoteAction.toggleShortcutReference.label)
                        .font(SettingsStyle.Typography.pageTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(model.activeProfile.name) · \(model.controllerProfile.name)")
                        .font(SettingsStyle.Typography.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if !model.enabled {
                    Label("映射已暂停", systemImage: "pause.circle")
                        .font(SettingsStyle.Typography.body)
                        .foregroundStyle(.secondary)
                }
                Button("关闭", action: close)
            }
            .padding(.horizontal, SettingsStyle.panelPadding)
            .padding(.vertical, SettingsStyle.Spacing.inline)
            Divider()
            GeometryReader { geometry in
                let minimum = ShortcutReferenceController.minimumSize
                ScrollView([.horizontal, .vertical]) {
                    ControllerMappingDiagram(model: model)
                        .padding(SettingsStyle.panelPadding)
                        .frame(width: max(geometry.size.width, minimum.width),
                               height: max(geometry.size.height, minimumDiagramHeight))
                }
            }
        }
        .background(SettingsStyle.pageBackground)
        .clipShape(.rect(cornerRadius: SettingsStyle.panelRadius))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsStyle.panelRadius)
                .strokeBorder(Color.primary.opacity(0.12))
                .allowsHitTesting(false)
        }
        .environment(\.appColorMode, model.colorMode)
        .preferredColorScheme(model.themeMode.colorScheme)
        .tint(model.colorMode.palette.selectionTint)
    }
}
