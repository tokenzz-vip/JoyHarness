import CoreBluetooth
import Foundation

@MainActor
final class JoyCon2Bluetooth: NSObject, ControllerTransport, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    @MainActor
    private final class Session {
        let peripheral: CBPeripheral
        let profile: JoyConProfile
        let commands = CommandQueue()
        var command: CBCharacteristic?
        var notifications: Set<CBUUID> = []
        var started = false
        var initialized = false
        var latest: JoyConSnapshot?
        var watchdog: DispatchWorkItem?
        var id: String { "ble-\(peripheral.identifier.uuidString)" }
        init(_ peripheral: CBPeripheral, _ profile: JoyConProfile) { self.peripheral = peripheral; self.profile = profile }
    }
    private var central: CBCentralManager?
    private var sessions: [UUID: Session] = [:]
    // A cancellation finishes asynchronously. Hold the identity until its terminal callback.
    private var cancelling: Set<UUID> = []
    private var active = false
    var onDevice: ((ConnectedJoyCon) -> Void)?
    var onInput: ((String, JoyConProfile, JoyConSnapshot) -> Void)?
    var onDisconnect: ((String) -> Void)?
    var onStatus: ((String) -> Void)?

    func start() {
        active = true
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else if central?.state == .poweredOn { scan() }
    }
    func stop() {
        active = false; central?.stopScan()
        for session in Array(sessions.values) {
            cancelConnection(session)
            drop(session, message: "已断开")
        }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: if active { scan() }
        case .unauthorized: onStatus?("二代：请在系统设置中允许 JoyHarness 使用蓝牙。")
        case .poweredOff: onStatus?("二代：蓝牙已关闭。")
        case .unsupported: onStatus?("二代：本机不支持 BLE。")
        default: onStatus?("二代：蓝牙正在准备。")
        }
        if central.state != .poweredOn {
            cancelling.removeAll()
            for session in Array(sessions.values) { drop(session, message: "蓝牙不可用") }
        }
    }
    private func scan() {
        // Nintendo does not reliably advertise its service UUID. The exact
        // manufacturer signature is checked before connecting to a peripheral.
        guard let central, central.state == .poweredOn else { return }
        if central.isScanning { central.stopScan() }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        onStatus?("二代：正在扫描，长按手柄侧面的 SYNC 键")
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard active, sessions[peripheral.identifier] == nil, !cancelling.contains(peripheral.identifier),
              let profile = JoyConProfile.advertisement(advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data) else { return }
        let session = Session(peripheral, profile)
        sessions[peripheral.identifier] = session; peripheral.delegate = self
        onDevice?(.init(id: session.id, profile: profile, status: "正在连接 BLE"))
        armWatchdog(session, message: "连接或初始化超时，请按 SYNC 后重新扫描。")
        central.connect(peripheral)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard active, let session = sessions[peripheral.identifier], session.peripheral === peripheral else { central.cancelPeripheralConnection(peripheral); return }
        onDevice?(.init(id: session.id, profile: session.profile, status: "正在发现服务"))
        peripheral.discoverServices([CBUUID(string: JoyConProfile.service)])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if cancelling.remove(peripheral.identifier) != nil {
            if active { scan() }
            return
        }
        if let session = sessions[peripheral.identifier], session.peripheral === peripheral {
            drop(session, message: "连接失败：\(error?.localizedDescription ?? "请重新扫描")")
        }
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if cancelling.remove(peripheral.identifier) == nil,
           let session = sessions[peripheral.identifier], session.peripheral === peripheral {
            drop(session, message: "已断开，按 SYNC 后重新扫描")
        }
        if active { scan() }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let session = sessions[peripheral.identifier], session.peripheral === peripheral else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: JoyConProfile.service) }) else {
            fail(session, "未找到 Joy-Con 2 服务"); return
        }
        peripheral.discoverCharacteristics([CBUUID(string: JoyConProfile.command), CBUUID(string: JoyConProfile.reply),
                                             CBUUID(string: session.profile.inputCharacteristic)], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let session = sessions[peripheral.identifier], session.peripheral === peripheral else { return }
        guard error == nil, let chars = service.characteristics,
              let command = chars.first(where: { $0.uuid == CBUUID(string: JoyConProfile.command) }),
              let reply = chars.first(where: { $0.uuid == CBUUID(string: JoyConProfile.reply) }),
              let input = chars.first(where: { $0.uuid == CBUUID(string: session.profile.inputCharacteristic) }),
              command.properties.contains(.write) || command.properties.contains(.writeWithoutResponse),
              reply.properties.contains(.notify), input.properties.contains(.notify) else {
            fail(session, "手柄 GATT 特征不可用"); return
        }
        session.command = command
        peripheral.setNotifyValue(true, for: reply)
        peripheral.setNotifyValue(true, for: input)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard let session = sessions[peripheral.identifier], session.peripheral === peripheral else { return }
        guard error == nil, characteristic.isNotifying else { fail(session, "无法订阅手柄输入"); return }
        session.notifications.insert(characteristic.uuid)
        guard session.notifications.count == 2, !session.started else { return }
        session.started = true
        onDevice?(.init(id: session.id, profile: session.profile, status: "正在初始化 BLE 协议"))
        session.commands.write = { [weak session] bytes in
            guard let session, let characteristic = session.command else { return false }
            let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
            guard bytes.count <= session.peripheral.maximumWriteValueLength(for: type),
                  type == .withResponse || session.peripheral.canSendWriteWithoutResponse else { return false }
            session.peripheral.writeValue(Data(bytes), for: characteristic, type: type)
            return true
        }
        session.commands.failed = { [weak self, weak session] message in
            guard let session else { return }; self?.fail(session, message)
        }
        session.commands.completed = { [weak self, weak session] in
            guard let self, let session else { return }
            session.initialized = true
            if let snapshot = session.latest { self.deliver(snapshot, session: session) }
        }
        session.commands.start(ControllerCommand.secondGenerationStartup)
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error, let session = sessions[peripheral.identifier], session.peripheral === peripheral { fail(session, "BLE 写入失败：\(error.localizedDescription)") }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let session = sessions[peripheral.identifier], session.peripheral === peripheral, let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        if characteristic.uuid == CBUUID(string: JoyConProfile.reply), bytes.count >= 8 {
            session.commands.reply(command: bytes[0], subcommand: bytes[3], success: bytes[1] & 1 != 0)
        } else if characteristic.uuid == CBUUID(string: session.profile.inputCharacteristic),
                  let snapshot = JoyConDecoder.secondGeneration(bytes, side: session.profile.side) {
            session.latest = snapshot; session.commands.inputReceived()
            if session.initialized { deliver(snapshot, session: session) }
        }
    }
    private func deliver(_ snapshot: JoyConSnapshot, session: Session) {
        session.watchdog?.cancel()
        onDevice?(.init(id: session.id, profile: session.profile, status: "已连接 · Bluetooth LE", ready: true, battery: snapshot.battery))
        onInput?(session.id, session.profile, snapshot)
    }
    private func armWatchdog(_ session: Session, message: String) {
        session.watchdog?.cancel()
        let work = DispatchWorkItem { [weak self, weak session] in
            guard let session else { return }; self?.fail(session, message)
        }
        session.watchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: work)
    }
    private func fail(_ session: Session, _ message: String) {
        Log.bluetooth.error("Joy-Con 2 connection failed: \(message, privacy: .private)")
        cancelConnection(session)
        drop(session, message: message)
    }
    private func cancelConnection(_ session: Session) {
        guard let central, central.state == .poweredOn else { return }
        cancelling.insert(session.peripheral.identifier)
        if session.peripheral.state != .disconnected {
            central.cancelPeripheralConnection(session.peripheral)
        }
    }

    private func drop(_ session: Session, message: String) {
        session.commands.cancel(); session.watchdog?.cancel(); session.peripheral.delegate = nil
        sessions[session.peripheral.identifier] = nil
        onDisconnect?(session.id)
        onDevice?(.init(id: session.id, profile: session.profile, status: message))
    }
}
