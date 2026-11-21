import AppKit
import SwiftUI

/// Uses native menu items so colored trailing indicators retain their color
/// even for the disabled, checked current model.
@MainActor
struct ControllerDeviceMenu<Label: View>: View {
    @ObservedObject var model: DashboardModel
    @ViewBuilder var label: Label

    var body: some View {
        label
            .accessibilityHidden(true)
            .overlay { ControllerDeviceMenuAnchor(model: model) }
    }
}

@MainActor
enum ControllerDeviceMenuContent {
    static func make(model: DashboardModel, target: AnyObject?, action: Selector?) -> NSMenu {
        let menu = NSMenu(title: "更换手柄")
        menu.autoenablesItems = false
        let connectedDevices = model.connectedDevices
        var entries: [(name: String, id: String, connected: Bool, selected: Bool)] = []
        for profile in JoyConProfile.all {
            let devices = connectedDevices.filter { $0.profile == profile }
            if devices.isEmpty {
                let selected = model.controllerSelection.profileID == profile.id && model.controllerSelection.deviceID == nil
                entries.append((profile.name, "profile:" + profile.id, false, selected))
            }
            for device in devices {
                let name = profile.name + (devices.count > 1 ? " · " + device.identitySuffix : "")
                entries.append((name, device.id, true, model.controllerSelection.deviceID == device.id))
            }
        }
        let font = NSFont.menuFont(ofSize: 0)
        let titleWidth = entries.map { ($0.name as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: ceil(titleWidth) + 26)]
        func styledTitle(_ name: String, connected: Bool) -> NSAttributedString {
            let title = NSMutableAttributedString(string: name + "\t●", attributes: [.font: font, .paragraphStyle: paragraph])
            title.addAttributes([.foregroundColor: connected ? NSColor.systemGreen : NSColor.systemGray,
                                 .font: NSFont.systemFont(ofSize: 9), .baselineOffset: 1],
                                range: NSRange(location: title.length - 1, length: 1))
            return title
        }
        for entry in entries {
            let item = NSMenuItem(title: entry.name, action: action, keyEquivalent: "")
            item.attributedTitle = styledTitle(entry.name, connected: entry.connected)
            item.target = target
            item.representedObject = entry.id
            item.state = entry.selected ? .on : .off
            item.isEnabled = !entry.connected || !entry.selected
            item.toolTip = entry.connected ? "已连接" : "选择后等待此型号手柄"
            item.setAccessibilityLabel(entry.name + (entry.connected ? "，已连接" : "，未连接"))
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let hint = NSMenuItem(title: "仅选中的手柄生效", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        return menu
    }

    static func select(_ item: NSMenuItem, model: DashboardModel) {
        guard let id = item.representedObject as? String else { return }
        if let profile = JoyConProfile.all.first(where: { "profile:" + $0.id == id }) {
            model.selectControllerProfile(profile)
        } else {
            model.selectDevice(id)
        }
    }
}

@MainActor
private struct ControllerDeviceMenuAnchor: NSViewRepresentable {
    @ObservedObject var model: DashboardModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.openMenu(_:)))
        button.isBordered = false
        button.isTransparent = true
        button.setAccessibilityRole(.popUpButton)
        button.setAccessibilityHelp("选择唯一生效的手柄")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.model = model
        button.setAccessibilityLabel("更换手柄，当前：\(model.controllerTitle)")
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    @MainActor
    final class Coordinator: NSObject {
        var model: DashboardModel

        init(model: DashboardModel) { self.model = model }

        @objc func openMenu(_ sender: NSButton) {
            let menu = ControllerDeviceMenuContent.make(model: model, target: self, action: #selector(selectController(_:)))
            // NSButton uses flipped coordinates: its bottom edge is maxY.
            let bottom = sender.isFlipped ? sender.bounds.maxY + 5 : sender.bounds.minY - 5
            menu.popUp(positioning: nil, at: NSPoint(x: sender.bounds.minX, y: bottom), in: sender)
        }

        @objc private func selectController(_ sender: NSMenuItem) {
            ControllerDeviceMenuContent.select(sender, model: model)
        }
    }
}
