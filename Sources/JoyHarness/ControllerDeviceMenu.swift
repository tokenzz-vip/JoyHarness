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
        let names = JoyConProfile.all.flatMap { profile -> [String] in
            let devices = model.devices.filter { $0.profile == profile }
            let names = devices.map { profile.name + (devices.count > 1 ? " · " + $0.identitySuffix : "") }
            if devices.contains(where: \.ready) { return names }
            return names + [devices.isEmpty ? profile.name : "等待 " + profile.name]
        }
        let font = NSFont.menuFont(ofSize: 0)
        let titleWidth = names.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: ceil(titleWidth) + 26)]
        func styledTitle(_ name: String, connected: Bool) -> NSAttributedString {
            let title = NSMutableAttributedString(string: name + "\t●", attributes: [.font: font, .paragraphStyle: paragraph])
            title.addAttributes([.foregroundColor: connected ? NSColor.systemGreen : NSColor.systemGray,
                                 .font: NSFont.systemFont(ofSize: 9), .baselineOffset: 1],
                                range: NSRange(location: title.length - 1, length: 1))
            return title
        }
        for profile in JoyConProfile.all {
            let devices = model.devices.filter { $0.profile == profile }
            if !devices.contains(where: \.ready) {
                let title = devices.isEmpty ? profile.name : "等待 " + profile.name
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.attributedTitle = styledTitle(title, connected: false)
                item.setAccessibilityLabel(title + "，未连接")
                item.target = target
                item.representedObject = "profile:" + profile.id
                item.state = model.controllerSelection.profileID == profile.id && model.controllerSelection.deviceID == nil ? .on : .off
                item.toolTip = "未连接；选择后等待此型号手柄"
                menu.addItem(item)
            }
            for device in devices {
                let name = profile.name + (devices.count > 1 ? " · " + device.identitySuffix : "")
                let item = NSMenuItem(title: name, action: action, keyEquivalent: "")
                item.attributedTitle = styledTitle(name, connected: device.ready)
                item.target = target
                item.representedObject = device.id
                item.state = model.controllerSelection.deviceID == device.id ? .on : .off
                item.isEnabled = model.controllerSelection.deviceID != device.id
                item.toolTip = device.ready ? "已连接" : device.status
                item.setAccessibilityLabel(name + "，" + (device.ready ? "已连接" : "未连接"))
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let hint = NSMenuItem(title: "仅选中的手柄生效", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        return menu
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
            guard let id = sender.representedObject as? String else { return }
            if id.hasPrefix("profile:"), let profile = JoyConProfile.all.first(where: { "profile:" + $0.id == id }) {
                model.selectControllerProfile(profile)
            } else { model.selectDevice(id) }
        }
    }
}
