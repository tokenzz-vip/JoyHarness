import Foundation
import IOKit.hid

@MainActor
final class JoyConHID: ControllerTransport {
    @MainActor
    private final class Session {
        let device: IOHIDDevice
        let profile: JoyConProfile
        var id: String
        let needsAddress: Bool
        var previousID: String?
        let buffer: UnsafeMutablePointer<UInt8>
        let commands = CommandQueue()
        var initialized = false
        var ready = false
        var watchdog: DispatchWorkItem?
        var batteryEstimate: (percent: Int, expiresAt: TimeInterval)?
        var nextBatteryQuery: TimeInterval = 0
        var batteryQueryCounter: UInt8 = 3
        weak var owner: JoyConHID?
        init(device: IOHIDDevice, profile: JoyConProfile, id: String, needsAddress: Bool, owner: JoyConHID) {
            self.device = device; self.profile = profile; self.id = id; self.owner = owner
            self.needsAddress = needsAddress
            buffer = .allocate(capacity: 128); buffer.initialize(repeating: 0, count: 128)
        }
        deinit { buffer.deallocate() }
    }
    private static let batteryQueryInterval: TimeInterval = 60
    private let runLoopMode = CFRunLoopMode.commonModes.rawValue
    private var manager: IOHIDManager?
    private var sessions: [ObjectIdentifier: Session] = [:]
    var onDevice: ((ConnectedJoyCon) -> Void)?
    var onInput: ((String, JoyConProfile, JoyConSnapshot) -> Void)?
    var onDisconnect: ((String) -> Void)?
    var onStatus: ((String) -> Void)?

    func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        let matches = JoyConProfile.all.filter { $0.generation == .first }.map {
            [kIOHIDVendorIDKey as String: JoyConProfile.vendorID, kIOHIDProductIDKey as String: $0.productID]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, _, device in
            guard let context, result == kIOReturnSuccess else { return }
            MainActor.assumeIsolated { Unmanaged<JoyConHID>.fromOpaque(context).takeUnretainedValue().attach(device) }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            MainActor.assumeIsolated {
                let transport = Unmanaged<JoyConHID>.fromOpaque(context).takeUnretainedValue()
                if let session = transport.sessions[ObjectIdentifier(device)] {
                    Log.hid.notice("System removed HID device: \(session.profile.id, privacy: .public)")
                }
                transport.remove(device)
            }
        }, context)
        // Deliver reports in the same modes as the watchdog, including menu tracking.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), runLoopMode)
        let result = IOHIDManagerOpen(manager, 0)
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), runLoopMode)
            onStatus?("一代 HID 无法打开（\(result)），请检查输入监控权限。")
            return
        }
        self.manager = manager
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> { devices.forEach(attach) }
        onStatus?("一代：等待系统蓝牙中已配对的 Joy-Con")
    }
    func stop() {
        for session in Array(sessions.values) { remove(session.device) }
        guard let manager else { return }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), runLoopMode)
        IOHIDManagerClose(manager, 0)
        self.manager = nil
    }
    private func attach(_ device: IOHIDDevice) {
        guard sessions[ObjectIdentifier(device)] == nil,
              let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
              let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int,
              let profile = JoyConProfile.hid(vendor: vendor, product: product) else { return }
        var registryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &registryID)
        let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String
        let usableSerial = serial.flatMap { $0.isEmpty ? nil : $0 }
        let fallback = registryID == 0 ? UUID().uuidString : String(registryID)
        let id = "hid-\(profile.id)-\(usableSerial ?? fallback)"
        let session = Session(device: device, profile: profile, id: id, needsAddress: usableSerial == nil, owner: self)
        sessions[ObjectIdentifier(device)] = session
        if !session.needsAddress { onDevice?(.init(id: id, profile: profile)) }
        IOHIDDeviceRegisterInputReportCallback(device, session.buffer, 128, { context, result, _, _, reportID, bytes, length in
            guard let context, result == kIOReturnSuccess, length > 0 else { return }
            MainActor.assumeIsolated {
                let session = Unmanaged<Session>.fromOpaque(context).takeUnretainedValue()
                var report = Array(UnsafeBufferPointer(start: bytes, count: length))
                if report.first != UInt8(reportID) { report.insert(UInt8(reportID), at: 0) }
                session.owner?.receive(report, session: session)
            }
        }, Unmanaged.passUnretained(session).toOpaque())
        session.commands.write = { [weak session] bytes in
            guard let session else { return false }
            let result = bytes.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(session.device, kIOHIDReportTypeOutput, CFIndex(bytes[0]), $0.baseAddress!, bytes.count)
            }
            return result == kIOReturnSuccess
        }
        session.commands.failed = { [weak self, weak session] message in
            guard let session else { return }; session.ready = false
            self?.onDisconnect?(session.id)
            self?.onDevice?(.init(id: session.id, profile: profile, status: message))
        }
        session.commands.completed = { [weak session] in session?.initialized = true }
        var startup: [ControllerCommand] = [.hid(3, payload: [0x30], counter: 0), .hid(0x30, payload: [1], counter: 1)]
        if session.needsAddress { startup.append(.hid(0x02, payload: [], counter: 2, optional: true)) }
        session.commands.start(startup)
        let watchdog = DispatchWorkItem { [weak self, weak session] in
            guard let session, !session.ready else { return }
            session.commands.cancel()
            self?.onDevice?(.init(id: session.id, profile: profile, status: "未收到完整输入，请重新扫描或重新配对。"))
        }
        session.watchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: watchdog)
    }
    private func receive(_ bytes: [UInt8], session: Session) {
        if bytes.first == 0x21, bytes.count >= 15 {
            if bytes[14] == 0x50 {
                guard session.ready, session.nextBatteryQuery > 0 else { return }
                session.batteryEstimate = JoyConDecoder.firstGenerationBatteryEstimate(bytes).map {
                    ($0, ProcessInfo.processInfo.systemUptime + Self.batteryQueryInterval + 2)
                }
                return
            }
            if session.needsAddress, !session.initialized, session.commands.running, session.previousID == nil,
               let address = JoyConDecoder.firstGenerationAddress(bytes) {
                session.previousID = session.id
                session.id = "hid-\(session.profile.id)-bt-\(address)"
            }
            session.commands.reply(command: bytes[14], success: bytes[13] & 0x80 != 0)
        }
        guard session.initialized, let snapshot = JoyConDecoder.firstGeneration(bytes, side: session.profile.side) else { return }
        if !session.ready {
            session.ready = true
            session.watchdog?.cancel()
            Log.hid.notice("Receiving HID reports: \(session.profile.id, privacy: .public)")
        }
        let now = ProcessInfo.processInfo.systemUptime
        if snapshot.charging {
            session.batteryEstimate = nil
            session.nextBatteryQuery = 0
        } else if bytes.first == 0x30, now >= session.nextBatteryQuery {
            // Battery polling is independent of initialization and never retries a failed write.
            session.nextBatteryQuery = now + Self.batteryQueryInterval
            let query = ControllerCommand.hid(0x50, payload: [], counter: session.batteryQueryCounter)
            session.batteryQueryCounter = (session.batteryQueryCounter + 1) & 0x0f
            if session.commands.write?(query.data) != true { session.batteryEstimate = nil }
        }
        let estimate = session.batteryEstimate.flatMap { now < $0.expiresAt ? $0.percent : nil }
        onDevice?(.init(id: session.id, profile: session.profile, status: "已连接 · Bluetooth HID", ready: true,
                        battery: estimate ?? snapshot.battery, previousID: session.previousID))
        onInput?(session.id, session.profile, snapshot)
    }
    private func remove(_ device: IOHIDDevice) {
        guard let session = sessions.removeValue(forKey: ObjectIdentifier(device)) else { return }
        IOHIDDeviceRegisterInputReportCallback(device, session.buffer, 128, nil, nil)
        session.commands.cancel(); session.watchdog?.cancel()
        onDisconnect?(session.id)
        onDevice?(.init(id: session.id, profile: session.profile, status: "已断开"))
    }
}
