import SwiftUI

enum SetupStep: String, CaseIterable, Codable, Identifiable {
    case welcome, permissions, controller, voice, trial, complete

    var id: Self { self }
    var index: Int { Self.allCases.firstIndex(of: self)! }
    var title: String {
        switch self {
        case .welcome: "欢迎使用"
        case .permissions: "系统权限"
        case .controller: "连接手柄"
        case .voice: "语音快捷键"
        case .trial: "试用按键"
        case .complete: "设置完成"
        }
    }
}

struct SetupReadiness {
    var profile: JoyConProfile?
    var accessibility: Bool
    var inputMonitoring: Bool
    var bluetooth: Bool
    var connected: Bool

    var permissionHint: String? {
        guard let profile else { return "请选择要使用的手柄型号。" }
        if !accessibility { return "开启辅助功能后即可继续。" }
        if profile.generation == .first && !inputMonitoring { return "一代 Joy-Con 需要输入监控权限。" }
        if profile.generation == .second && !bluetooth { return "Joy-Con 2 需要蓝牙访问权限。" }
        return nil
    }
}

@MainActor
final class SetupFlow: ObservableObject {
    private struct Progress: Codable {
        var step: SetupStep = .welcome
        var completed = false
    }

    @Published private(set) var step: SetupStep
    @Published private(set) var completed: Bool
    @Published private(set) var isPresented = false
    @Published private(set) var testedButtons: Set<ControllerInput> = []
    private let defaults: UserDefaults
    private static let key = "setupProgress.v1"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let progress = SettingsStorage.load(Progress.self, Self.key, defaults: defaults) ?? Progress()
        step = progress.step == .complete ? .trial : progress.step
        completed = progress.completed
    }

    func present() {
        guard !isPresented else { return }
        if completed { step = .welcome }
        isPresented = true
    }

    func pause() {
        guard isPresented else { return }
        isPresented = false
        if step == .complete { step = .trial }
        resetTrial()
        save()
    }

    func blockingHint(_ readiness: SetupReadiness) -> String? {
        if step == .welcome { return nil }
        if let hint = readiness.permissionHint {
            return step == .permissions ? hint : "请返回「系统权限」检查当前手柄所需的权限。"
        }
        if step == .permissions { return nil }
        if !readiness.connected { return "等待选中的手柄连接，可从「连接手柄」重新扫描。" }
        if step.index >= SetupStep.trial.index && testedButtons.isEmpty {
            return "请在「试用按键」按一下选中手柄上的实体按键。"
        }
        return nil
    }

    func advance(_ readiness: SetupReadiness) {
        guard isPresented, blockingHint(readiness) == nil else { return }
        if step == .complete {
            completed = true
            isPresented = false
            resetTrial()
        } else {
            step = SetupStep.allCases[step.index + 1]
        }
        save()
    }

    func goBack(to destination: SetupStep) {
        guard isPresented, destination.index < step.index else { return }
        step = destination
        resetTrial()
        save()
    }

    func observeButtons(_ buttons: Set<ControllerInput>) {
        guard isPresented, step == .trial, !buttons.isSubset(of: testedButtons) else { return }
        testedButtons.formUnion(buttons)
    }

    func resetTrial() {
        if !testedButtons.isEmpty { testedButtons = [] }
    }

    private func save() {
        SettingsStorage.save(Progress(step: step, completed: completed), Self.key, defaults: defaults)
    }
}
