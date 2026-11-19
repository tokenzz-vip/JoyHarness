import Foundation

/// App actions mirror RcHarness; the physical slots work on either Joy-Con half.
enum DefaultKeyProfiles {
    static let version = 2
    static let presetIDs = Set(HarnessApplication.defaults.map { id(for: $0) })

    static func id(for application: HarnessApplication) -> UUID {
        let index = HarnessApplication.defaults.firstIndex { $0.id == application.id }! + 1
        return UUID(uuidString: String(format: "C0DE0013-0000-0000-0000-%012d", index))!
    }

    static func name(for application: HarnessApplication) -> String { application.name + " 按键方案" }

    static func profile(for application: HarnessApplication, macros: [ActionMacro]) -> KeyProfile {
        let preset = preset(for: application.id)
        func action(_ suffix: String) -> ButtonMapping {
            let name = application.name + "-" + suffix
            let definition = DefaultMacros.all.first { $0.name == name }
            let macro = macros.first { $0.id == definition?.id }
                ?? macros.first { $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(name) == .orderedSame }
            return macro.map { .init(action: .macro, macroID: $0.id) } ?? .init()
        }
        var mapping = RemoteMapping.defaults
        let left: [ControllerInput] = [.up, .right, .down, .left, .l, .zl]
        let right: [ControllerInput] = [.x, .a, .b, .y, .r, .zr]
        for slots in [left, right] {
            for (input, name) in zip(slots, preset.navigation) { mapping[input, .double] = action(name) }
        }
        for input in [ControllerInput.leftStick, .rightStick] { mapping[input, .double] = action(preset.newConversation) }
        for input in [ControllerInput.minus, .plus] {
            mapping[input, .double] = action(preset.menu)
            mapping[input, .long] = action(preset.alternateMenu)
        }
        for input in [ControllerInput.leftSL, .rightSL] { mapping[input, .double] = action(preset.previous) }
        for input in [ControllerInput.leftSR, .rightSR] { mapping[input, .double] = action(preset.next) }
        return KeyProfile(id: id(for: application), name: name(for: application), mapping: mapping)
    }

    private struct Preset {
        let newConversation: String
        /// Up / X, right / A, down / B, left / Y, L / R, ZL / ZR.
        let navigation: [String]
        let menu: String
        let alternateMenu: String
        var previous = "上一个会话"
        var next = "下一个会话"
    }

    private static func preset(for id: String) -> Preset {
        switch id {
        case "chatgpt":
            return .init(newConversation: "新建会话", navigation: (1...6).map { "转到最近聊天\($0)" },
                         menu: "切换会话与标签页", alternateMenu: "新建独立会话")
        case "claude":
            return .init(newConversation: "新建会话", navigation: (1...6).map { "选择环境\($0)" },
                         menu: "切换会话（Control+Tab）", alternateMenu: "新建环境")
        case "cursor":
            return .init(newConversation: "新建会话（Command+N）",
                         navigation: ["切换侧边面板（Command+I）", "下一个会话", "打开命令面板", "上一个会话", "循环切换 AI 模型", "循环切换 Agent 模式"],
                         menu: "切换 Agent 布局", alternateMenu: "新建会话标签页")
        case "deepseek":
            return .init(newConversation: "新建会话",
                         navigation: ["搜索会话", "切换右侧面板", "浏览工作区文件", "切换左侧栏", "放大内容字号", "缩小内容字号"],
                         menu: "搜索会话", alternateMenu: "分叉会话", previous: "分割面板", next: "切换面板全屏")
        case "workbuddy":
            return .init(newConversation: "新建对话",
                         navigation: ["定位当前任务", "下一个任务", "全局搜索", "上一个任务", "放大内容字号", "缩小内容字号"],
                         menu: "切换左侧栏", alternateMenu: "新建快速问答", previous: "上一个任务", next: "下一个任务")
        case "opencode":
            return .init(newConversation: "新建会话（Command+N）", navigation: (1...6).map { "转到会话标签页\($0)" },
                         menu: "切换侧边栏", alternateMenu: "新建窗口")
        default: preconditionFailure("Unknown built-in Harness: \(id)")
        }
    }
}

extension Configuration {
    /// Existing profiles and explicit Harness bindings survive upgrades and imports.
    /// The marker preserves later edits, renames and deletions of these presets.
    func addingBuiltInProfiles() -> Self {
        let savedVersion = profilePresetsVersion ?? 0
        guard savedVersion < DefaultKeyProfiles.version else { return self }
        var result = self
        // Stabilize the fallback before the editor selection can change.
        result.defaultProfileID = defaultProfileID ?? profiles.first?.id
        func availableName(_ base: String, excluding id: UUID) -> String {
            var name = base
            var number = 2
            while result.profiles.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                name = base + " \(number)"
                number += 1
            }
            return name
        }
        let chatGPT = HarnessApplication.chatGPT
        if let index = result.profiles.firstIndex(where: { $0.id == DefaultKeyProfiles.id(for: chatGPT) }) {
            let profile = result.profiles[index]
            result.profiles[index].name = availableName(DefaultKeyProfiles.name(for: chatGPT), excluding: profile.id)
        }
        if savedVersion < 1 {
            for application in HarnessApplication.defaults {
                guard !result.profiles.contains(where: { $0.id == DefaultKeyProfiles.id(for: application) }) else { continue }
                var profile = DefaultKeyProfiles.profile(for: application, macros: macros)
                profile.name = availableName(profile.name, excluding: profile.id)
                result.profiles.append(profile)
            }
        }
        result.profilePresetsVersion = DefaultKeyProfiles.version
        return result
    }
}
