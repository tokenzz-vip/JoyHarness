import Foundation

enum JoyConSide: String, Codable, CaseIterable { case left, right
    var label: String { self == .left ? "左手柄" : "右手柄" }
}
enum JoyConGeneration: Int, Codable, CaseIterable { case first = 1, second = 2 }

/// All device identity and GATT constants live at the protocol boundary.
struct JoyConProfile: Equatable, Identifiable {
    let generation: JoyConGeneration
    let side: JoyConSide
    let productID: Int
    var id: String { "joycon-\(generation.rawValue)-\(side.rawValue)" }
    var name: String { "Joy-Con\(generation == .second ? " 2" : "") (\(side == .left ? "L" : "R"))" }
    static let vendorID = 0x057e
    static let all: [Self] = [
        .init(generation: .first, side: .left, productID: 0x2006),
        .init(generation: .first, side: .right, productID: 0x2007),
        .init(generation: .second, side: .left, productID: 0x2067),
        .init(generation: .second, side: .right, productID: 0x2066),
    ]
    static func hid(vendor: Int, product: Int) -> Self? {
        guard vendor == vendorID else { return nil }
        return all.first { $0.generation == .first && $0.productID == product }
    }
    /// CoreBluetooth includes the 2-byte company ID in manufacturer data.
    static func advertisement(_ data: Data?) -> Self? {
        guard let data else { return nil }
        let b = [UInt8](data)
        guard b.count >= 9, Array(b[0..<7]) == [0x53, 0x05, 1, 0, 3, 0x7e, 0x05] else { return nil }
        let product = Int(b[7]) | Int(b[8]) << 8
        return all.first { $0.generation == .second && $0.productID == product }
    }
    static let service = "ab7de9be-89fe-49ad-828f-118f09df7fd0"
    static let command = "649d4ac9-8eb7-4e6c-af44-1ea54fe5f005"
    static let reply = "c765a961-d9d8-4d36-a20a-5315b111836a"
    var inputCharacteristic: String {
        side == .left ? "cc1bbbb5-7354-4d32-a716-a81cb241a32a" : "d5a9e01e-2ffc-4cca-b20c-8b67142bf442"
    }
}

enum ControllerInput: String, CaseIterable, Codable, Identifiable {
    case a, b, x, y, up, down, left, right, l, r, zl, zr, minus, plus, leftStick, rightStick
    case capture, home, leftSL, leftSR, rightSL, rightSR, c, gl, gr
    case leftStickUp, leftStickDown, leftStickLeft, leftStickRight
    case rightStickUp, rightStickDown, rightStickLeft, rightStickRight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .a: "A"; case .b: "B"; case .x: "X"; case .y: "Y"
        case .up: "↑"; case .down: "↓"; case .left: "←"; case .right: "→"
        case .l: "L"; case .r: "R"; case .zl: "ZL"; case .zr: "ZR"
        case .minus: "−"; case .plus: "+"; case .leftStick: "左摇杆按下"; case .rightStick: "右摇杆按下"
        case .capture: "截图键"; case .home: "HOME"; case .leftSL: "左 SL"; case .leftSR: "左 SR"
        case .rightSL: "右 SL"; case .rightSR: "右 SR"; case .c: "C 键 · 二代"
        case .gl: "GL · 二代"; case .gr: "GR · 二代"
        case .leftStickUp: "左摇杆 ↑"; case .leftStickDown: "左摇杆 ↓"
        case .leftStickLeft: "左摇杆 ←"; case .leftStickRight: "左摇杆 →"
        case .rightStickUp: "右摇杆 ↑"; case .rightStickDown: "右摇杆 ↓"
        case .rightStickLeft: "右摇杆 ←"; case .rightStickRight: "右摇杆 →"
        }
    }
    var side: JoyConSide {
        switch self {
        case .up, .down, .left, .right, .l, .zl, .minus, .leftStick, .capture, .leftSL, .leftSR, .gl,
             .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight: .left
        default: .right
        }
    }
    var secondGenerationOnly: Bool { [.c, .gl, .gr].contains(self) }
    var isStickButton: Bool { self == .leftStick || self == .rightStick }
    var isStickDirection: Bool { Self.stickDirections(for: side).contains(self) }
    var defaultDirectionAction: RemoteAction? {
        guard let index = Self.stickDirections(for: side).firstIndex(of: self) else { return nil }
        return [.arrowUp, .arrowDown, .arrowLeft, .arrowRight][index]
    }
    /// Up, down, left, right; independent from the physical D-pad and stick press.
    static func stickDirections(for side: JoyConSide) -> [Self] {
        side == .left ? [.leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight]
            : [.rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight]
    }
    var symbol: String {
        switch self {
        case .up: "chevron.up"; case .down: "chevron.down"; case .left: "chevron.left"; case .right: "chevron.right"
        case .leftStickUp, .rightStickUp: "chevron.up"
        case .leftStickDown, .rightStickDown: "chevron.down"
        case .leftStickLeft, .rightStickLeft: "chevron.left"
        case .leftStickRight, .rightStickRight: "chevron.right"
        case .a: "a.circle"; case .b: "b.circle"; case .x: "x.circle"; case .y: "y.circle"
        case .l: "l.button.roundedbottom.horizontal"; case .r: "r.button.roundedbottom.horizontal"
        case .zl: "zl.button.roundedtop.horizontal"; case .zr: "zr.button.roundedtop.horizontal"
        case .minus: "minus.circle"; case .plus: "plus.circle"
        case .leftStick, .rightStick: "l.joystick"
        case .capture: "camera"; case .home: "house"; case .c: "c.circle"
        case .leftSL, .rightSL: "s.circle"; case .leftSR, .rightSR: "s.circle"
        case .gl, .gr: "g.circle"
        }
    }
}

enum Gesture: String, CaseIterable, Codable, Identifiable {
    case single, double, long
    var id: String { rawValue }
    var label: String { switch self { case .single: "单击"; case .double: "双击"; case .long: "长按" } }
}

enum HarnessFocusTarget: String {
    case chatgpt, claude, cursor, deepSeek = "deepseek", workBuddy = "workbuddy", openCode = "opencode"
}

enum RemoteAction: String, CaseIterable, Codable, Identifiable {
    case enter, backspace, escape, arrowUp, arrowDown, arrowLeft, arrowRight
    case toggleMode, cycleStickMode, cycleLeftStickMode, cycleRightStickMode, rightCommand, leftCommand, fn, leftOption, rightOption
    case copy, paste, browserBack, browserForward
    case mouseLeft, mouseRight, pointerUp, pointerDown, pointerLeft, pointerRight, scrollUp, scrollDown
    case volumeUp, volumeDown, mute, playPause, recordedShortcut, openApplication, phrase, openPhrases, macro, disabled
    case focusChatGPT, focusClaude, focusCursor, focusDeepSeek, focusWorkBuddy, focusOpenCode

    static let harnessFocusActions: [Self] = [.focusChatGPT, .focusClaude, .focusCursor, .focusDeepSeek, .focusWorkBuddy, .focusOpenCode]

    var canRunInMacro: Bool {
        switch self {
        case .toggleMode, .openPhrases, .cycleStickMode, .cycleLeftStickMode, .cycleRightStickMode: false
        default: true
        }
    }

    var harnessFocusTarget: HarnessFocusTarget? {
        switch self {
        case .focusChatGPT: .chatgpt
        case .focusClaude: .claude
        case .focusCursor: .cursor
        case .focusDeepSeek: .deepSeek
        case .focusWorkBuddy: .workBuddy
        case .focusOpenCode: .openCode
        default: nil
        }
    }
    var id: String { rawValue }
    var label: String {
        switch self {
        case .enter: "Enter"; case .backspace: "Backspace"; case .escape: "Escape"
        case .arrowUp: "方向键 ↑"; case .arrowDown: "方向键 ↓"; case .arrowLeft: "方向键 ←"; case .arrowRight: "方向键 →"
        case .cycleStickMode, .cycleLeftStickMode, .cycleRightStickMode: "切换摇杆模式"
        case .toggleMode: "暂停 / 恢复映射"; case .rightCommand: "按住右 Command"; case .leftCommand: "按住左 Command"
        case .fn: "按住 Fn / 地球键"; case .leftOption: "按住左 Option"; case .rightOption: "按住右 Option"
        case .copy: "复制 ⌘C"; case .paste: "粘贴 ⌘V"
        case .browserBack: "浏览器后退"; case .browserForward: "浏览器前进"
        case .mouseLeft: "鼠标左键"; case .mouseRight: "鼠标右键"
        case .pointerUp: "指针 ↑"; case .pointerDown: "指针 ↓"; case .pointerLeft: "指针 ←"; case .pointerRight: "指针 →"
        case .scrollUp: "向上滚动"; case .scrollDown: "向下滚动"; case .volumeUp: "音量 +"; case .volumeDown: "音量 −"
        case .mute: "静音"; case .playPause: "播放 / 暂停"; case .recordedShortcut: "自定义快捷键"
        case .openApplication: "打开应用"; case .phrase: "输入文本"; case .openPhrases: "唤出常用语"; case .macro: "组合动作"; case .disabled: "未设置"
        case .focusChatGPT: "打开聚焦ChatGPT"; case .focusClaude: "打开聚焦Claude"; case .focusCursor: "打开聚焦Cursor"
        case .focusDeepSeek: "打开聚焦DeepSeek"; case .focusWorkBuddy: "打开聚焦WorkBuddy"; case .focusOpenCode: "打开聚焦OpenCode"
        }
    }
}
struct RecordedShortcut: Codable, Equatable, Hashable {
    let keyCode: UInt16
    let modifiers: UInt64
    let label: String
}
struct ButtonMapping: Codable, Equatable, Hashable {
    var action: RemoteAction = .disabled
    var shortcut: RecordedShortcut?
    var applicationPath: String?
    var text: String?
    var macroID: UUID?
    var summary: String {
        switch action {
        case .recordedShortcut: shortcut?.label ?? action.label
        case .openApplication: applicationPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? action.label
        case .phrase: text?.isEmpty == false ? text! : action.label
        default: action.label
        }
    }
}
struct RemoteMapping: Codable, Equatable {
    var buttons: [String: ButtonMapping] = [:]
    subscript(_ input: ControllerInput, _ gesture: Gesture = .single) -> ButtonMapping {
        get {
            buttons["\(input.rawValue).\(gesture.rawValue)"]
                ?? ButtonMapping(action: gesture == .single ? input.defaultDirectionAction ?? .disabled : .disabled)
        }
        set { buttons["\(input.rawValue).\(gesture.rawValue)"] = newValue }
    }
    static var defaults: Self {
        var mapping = Self()
        let actions: [ControllerInput: RemoteAction] = [
            .a: .enter, .b: .escape, .x: .copy, .y: .paste,
            .up: .arrowUp, .down: .arrowDown, .left: .arrowLeft, .right: .arrowRight,
            .l: .browserBack, .r: .browserForward, .zl: .mouseRight, .zr: .mouseLeft,
            .minus: .volumeDown, .plus: .volumeUp, .home: .toggleMode,
            .leftStick: .mouseLeft, .rightStick: .mouseRight, .c: .rightCommand,
        ]
        for (input, action) in actions { mapping[input] = ButtonMapping(action: action) }
        // Joy-Con has no shared A button across both halves; the stick press is
        // the stable equivalent of RcHarness's long-press phrase trigger.
        mapping[.leftStick, .long] = ButtonMapping(action: .openPhrases)
        mapping[.rightStick, .long] = ButtonMapping(action: .openPhrases)
        return mapping
    }
}
enum StickMode: CaseIterable {
    case mapped, pointer
    var next: Self { self == .pointer ? .mapped : .pointer }
    var label: String { self == .pointer ? "鼠标模式" : "方向映射" }
    var symbol: String { self == .pointer ? "computermouse" : "l.joystick" }
}
enum MouseButtonRole: String, Codable, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var label: String { self == .left ? "鼠标左键" : "鼠标右键" }
}
struct MouseButtonBindings: Codable, Equatable {
    var left: ControllerInput?
    var right: ControllerInput?

    init(left: ControllerInput? = nil, right: ControllerInput? = nil) {
        self.left = left
        self.right = right
    }
}
struct KeyProfile: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = "默认方案"
    var mapping = RemoteMapping.defaults
}

enum PhraseLanguage: String, Codable { case chinese, english }

struct SavedPhrase: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var text: String
    var englishTitle: String = ""
    var englishText: String = ""

    var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        return englishTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名常用语" : englishTitle
    }

    private enum CodingKeys: String, CodingKey { case id, title, text, englishTitle, englishText }

    init(id: UUID = UUID(), title: String, text: String, englishTitle: String = "", englishText: String = "") {
        self.id = id; self.title = title; self.text = text; self.englishTitle = englishTitle; self.englishText = englishText
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        text = try values.decode(String.self, forKey: .text)
        englishTitle = try values.decodeIfPresent(String.self, forKey: .englishTitle) ?? ""
        englishText = try values.decodeIfPresent(String.self, forKey: .englishText) ?? ""
    }
}

/// The five positions used by the RcHarness-style phrase picker.
struct PhraseAssignments: Codable, Equatable {
    static let inputs: [ControllerInput] = [.up, .down, .left, .right, .a]
    var slots: [String: UUID] = [:]
    subscript(_ input: ControllerInput) -> UUID? {
        get { slots[input.rawValue] }
        set { guard Self.inputs.contains(input) else { return }; slots[input.rawValue] = newValue }
    }
}

struct HarnessBinding: Codable, Equatable, Identifiable {
    var id = UUID()
    var applicationPath: String
    var bundleID: String
    var profileID: UUID
    var enabled = true
    var name: String { builtIn?.name ?? URL(fileURLWithPath: applicationPath).deletingPathExtension().lastPathComponent }
}
struct MacroStep: Codable, Equatable, Identifiable {
    var id = UUID()
    var mapping = ButtonMapping(action: .enter)
    var delay: Double = 0.1
}
struct ActionMacro: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = "新组合动作"
    var steps: [MacroStep] = [.init()]
    var tagIDs: Set<String> = [MacroTag.general.id]

    init(id: UUID = UUID(), name: String = "新组合动作", steps: [MacroStep] = [.init()],
         tagIDs: Set<String> = [MacroTag.general.id]) {
        self.id = id; self.name = name; self.steps = steps; self.tagIDs = tagIDs
    }

    private enum CodingKeys: String, CodingKey { case id, name, steps, tagIDs }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        steps = try values.decode([MacroStep].self, forKey: .steps)
        tagIDs = try values.decodeIfPresent(Set<String>.self, forKey: .tagIDs) ?? DefaultMacros.legacyTagIDs(for: id)
    }

    func matches(tagID: String?, query: String) -> Bool {
        (tagID == nil || tagIDs.contains(tagID!)) &&
            (query.isEmpty || name.localizedStandardContains(query))
    }
}
struct StickCenter: Codable, Equatable { var x: Int; var y: Int }
struct Configuration: Codable, Equatable {
    var version = 1
    var profiles: [KeyProfile] = [.init()]
    var defaultProfileID: UUID?
    var globalButtons = Self.defaultGlobalButtons(from: .defaults)
    var mouseButtons: [String: MouseButtonBindings] = [:]
    var harnesses: [HarnessBinding] = []
    static let customMacroLimit = 100
    var macros: [ActionMacro] = []
    var customMacroCount: Int { macros.filter { !DefaultMacros.presetIDs.contains($0.id) }.count }
    var macroPresetsVersion: Int?
    var profilePresetsVersion: Int?
    var deadzone = 0.18
    var pointerSpeed = 14.0
    var centers: [String: StickCenter] = [:]
    var phrases: [SavedPhrase] = []
    var phrasePresetsVersion: Int?
    var phraseAssignments = PhraseAssignments()

    private enum CodingKeys: String, CodingKey {
        case version, profiles, defaultProfileID, globalButtons, mouseButtons, harnesses, macros, macroPresetsVersion, profilePresetsVersion, deadzone, pointerSpeed, centers, phrases, phraseAssignments
        case phrasePresetsVersion, globalGestureOverrides
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        profiles = try values.decodeIfPresent([KeyProfile].self, forKey: .profiles) ?? [.init()]
        defaultProfileID = try values.decodeIfPresent(UUID.self, forKey: .defaultProfileID)
        let defaultMapping = profiles.first { $0.id == defaultProfileID }?.mapping ?? profiles.first?.mapping ?? .defaults
        if let saved = try values.decodeIfPresent([String: [GlobalButton]].self, forKey: .globalButtons) {
            globalButtons = (try values.decodeIfPresent(Bool.self, forKey: .globalGestureOverrides) ?? false)
                ? saved : Self.migratingFactoryGlobalGestures(saved)
        } else {
            globalButtons = Self.defaultGlobalButtons(from: defaultMapping)
        }
        mouseButtons = try values.decodeIfPresent([String: MouseButtonBindings].self, forKey: .mouseButtons) ?? [:]
        harnesses = try values.decodeIfPresent([HarnessBinding].self, forKey: .harnesses) ?? []
        macros = try values.decodeIfPresent([ActionMacro].self, forKey: .macros) ?? []
        macroPresetsVersion = try values.decodeIfPresent(Int.self, forKey: .macroPresetsVersion)
        profilePresetsVersion = try values.decodeIfPresent(Int.self, forKey: .profilePresetsVersion)
        deadzone = try values.decodeIfPresent(Double.self, forKey: .deadzone) ?? 0.18
        pointerSpeed = try values.decodeIfPresent(Double.self, forKey: .pointerSpeed) ?? 14
        centers = try values.decodeIfPresent([String: StickCenter].self, forKey: .centers) ?? [:]
        phrases = try values.decodeIfPresent([SavedPhrase].self, forKey: .phrases) ?? []
        phrasePresetsVersion = try values.decodeIfPresent(Int.self, forKey: .phrasePresetsVersion)
        phraseAssignments = try values.decodeIfPresent(PhraseAssignments.self, forKey: .phraseAssignments) ?? .init()
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version); try values.encode(profiles, forKey: .profiles)
        try values.encode(globalButtons, forKey: .globalButtons)
        try values.encode(true, forKey: .globalGestureOverrides)
        try values.encode(mouseButtons, forKey: .mouseButtons)
        try values.encodeIfPresent(defaultProfileID, forKey: .defaultProfileID); try values.encode(harnesses, forKey: .harnesses)
        try values.encode(macros, forKey: .macros); try values.encodeIfPresent(macroPresetsVersion, forKey: .macroPresetsVersion)
        try values.encodeIfPresent(profilePresetsVersion, forKey: .profilePresetsVersion)
        try values.encode(deadzone, forKey: .deadzone); try values.encode(pointerSpeed, forKey: .pointerSpeed)
        try values.encode(centers, forKey: .centers); try values.encode(phrases, forKey: .phrases)
        try values.encodeIfPresent(phrasePresetsVersion, forKey: .phrasePresetsVersion)
        try values.encode(phraseAssignments, forKey: .phraseAssignments)
    }

    func validated() throws -> Self {
        guard version == 1, !profiles.isEmpty, profiles.count <= 100 + DefaultKeyProfiles.presetIDs.count,
              profiles.filter({ !DefaultKeyProfiles.presetIDs.contains($0.id) }).count <= 100,
              Set(profiles.map(\.id)).count == profiles.count,
              macroPresetsVersion == nil || macroPresetsVersion! >= 0,
              profilePresetsVersion == nil || profilePresetsVersion! >= 0,
              (phrasePresetsVersion ?? 0) >= 0,
              harnesses.count <= 500 + HarnessApplication.defaults.count,
              harnesses.filter({ !$0.isBuiltIn }).count <= 500,
              Set(macros.map(\.id)).count == macros.count,
              Set(harnesses.map(\.id)).count == harnesses.count,
              deadzone.isFinite, (0.05...0.6).contains(deadzone),
              pointerSpeed.isFinite, (1...40).contains(pointerSpeed),
              defaultProfileID == nil || profiles.contains(where: { $0.id == defaultProfileID }),
              Set(harnesses.map(\.canonicalBundleID)).count == harnesses.count,
              harnesses.allSatisfy({ h in profiles.contains { $0.id == h.profileID } }),
              Set(phrases.map(\.id)).count == phrases.count,
              phrases.count <= 500,
              Set(phraseAssignments.slots.values).isSubset(of: Set(phrases.map(\.id))),
              phraseAssignments.slots.keys.allSatisfy({ key in PhraseAssignments.inputs.contains(where: { $0.rawValue == key }) }),
              profiles.allSatisfy({ $0.mapping.buttons.values.allSatisfy(validMapping) }),
              Set(globalButtons.keys) == Set(JoyConProfile.all.map(\.id)),
              mouseButtons.allSatisfy({ key, bindings in
                  guard let profile = JoyConProfile.all.first(where: { $0.id == key }) else { return false }
                  let global = Set(globalButtons[profile.id, default: []].compactMap(\.input))
                  let available = Set(profile.physicalInputs.filter { !$0.isStickButton && !global.contains($0) })
                  let selected = [bindings.left, bindings.right].compactMap { $0 }
                  return Set(selected).count == selected.count && selected.allSatisfy(available.contains)
              }),
              JoyConProfile.all.allSatisfy({ profile in
                  guard let buttons = globalButtons[profile.id], buttons.first?.input != nil else { return false }
                  let inputs = buttons.compactMap(\.input)
                  return Set(buttons.map(\.id)).count == buttons.count
                      && Set(inputs).count == inputs.count
                      && Set(inputs).isSubset(of: Set(profile.physicalInputs))
                      && buttons.allSatisfy { $0.actions.values.allSatisfy(validMapping) }
              }),
              macros.allSatisfy({ $0.steps.count <= 100 && $0.steps.allSatisfy {
                  $0.delay.isFinite && (0...30).contains($0.delay) && validMapping($0.mapping)
              } && (try? MacroExecutionPlan($0, macros: macros)) != nil }),
              centers.values.allSatisfy({ (0...4095).contains($0.x) && (0...4095).contains($0.y) })
        else { throw ConfigurationError.invalid }
        return self
    }
    private func validMapping(_ mapping: ButtonMapping) -> Bool {
        switch mapping.action {
        case .macro: return macros.contains { $0.id == mapping.macroID }
        case .recordedShortcut: return mapping.shortcut.map { $0.keyCode <= 127 } ?? false
        case .openApplication: return mapping.applicationPath?.hasPrefix("/") == true
        case .phrase: return mapping.text?.isEmpty == false
        default: return true
        }
    }
    enum ConfigurationError: LocalizedError { case invalid
        var errorDescription: String? { "配置格式无效，或包含越界参数 / 无效的方案引用。" }
    }
}
struct UsageStatistics: Codable {
    var days: [String: [String: Int]] = [:]
    mutating func record(_ input: ControllerInput, date: Date = Date()) {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let key = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        days[key, default: [:]][input.rawValue, default: 0] += 1
    }
    var total: Int { days.values.flatMap(\.values).reduce(0, +) }
}
