import Foundation

struct ConnectedJoyCon: Identifiable, Equatable {
    let id: String
    let profile: JoyConProfile
    var status = "正在初始化"
    var ready = false
    var battery: Int?
    var previousID: String?
    var batteryLabel: String? {
        battery.map { "\($0)%" }
    }
}

@MainActor
protocol ControllerTransport: AnyObject {
    var onDevice: ((ConnectedJoyCon) -> Void)? { get set }
    var onInput: ((String, JoyConProfile, JoyConSnapshot) -> Void)? { get set }
    var onDisconnect: ((String) -> Void)? { get set }
    var onStatus: ((String) -> Void)? { get set }
    func start()
    func stop()
}
