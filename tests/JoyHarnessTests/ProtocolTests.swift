import Foundation
import Testing
@testable import JoyHarness

struct ProtocolTests {
    func neutralFirst() -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 49); b[0] = 0x30; b[2] = 0x80
        b[7] = 8; b[8] = 0x80; b[10] = 8; b[11] = 0x80
        return b
    }
    func neutralSecond() -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 63); b[1] = 0x20; b[6] = 8; b[7] = 0x80; return b
    }
    @Test func identities() {
        #expect(JoyConProfile.hid(vendor: 0x057e, product: 0x2006)?.side == .left)
        #expect(JoyConProfile.hid(vendor: 0x057e, product: 0x2067) == nil)
        #expect(JoyConProfile.hid(vendor: 1, product: 0x2006) == nil)
        #expect(JoyConProfile.advertisement(Data([0x53, 5, 1, 0, 3, 0x7e, 5, 0x66, 0x20]))?.side == .right)
        #expect(JoyConProfile.advertisement(Data([0x53, 5, 1, 0, 3, 0x7e, 5, 0x67, 0x20]))?.side == .left)
        #expect(JoyConProfile.advertisement(Data([0x53, 5, 1, 0, 3, 0x7e, 5, 0x69, 0x20])) == nil)
        #expect(JoyConProfile.advertisement(Data([0x7e, 5, 1, 0, 3, 0x7e, 5, 0x67, 0x20])) == nil)
        #expect(JoyConProfile.advertisement(nil) == nil)
    }
    @Test func firstGenerationLeftBits() {
        var b = neutralFirst(); b[5] = 0xff; b[4] = 0xff; b[3] = 0xff
        let state = JoyConDecoder.firstGeneration(b, side: .left)
        #expect(state?.buttons == [.down, .up, .right, .left, .leftSR, .leftSL, .l, .zl, .minus, .leftStick, .capture])
        #expect(state?.stick == .neutral); #expect(state?.battery == 100)
    }
    @Test func firstGenerationRightBits() {
        var b = neutralFirst(); b[3] = 0xff; b[4] = 0xff; b[5] = 0xff
        #expect(JoyConDecoder.firstGeneration(b, side: .right)?.buttons == [.y, .x, .b, .a, .rightSR, .rightSL, .r, .zr, .plus, .rightStick, .home])
    }
    @Test func firstGenerationChargingAndAck() {
        var b = neutralFirst(); b[2] = 0x50
        #expect(JoyConDecoder.firstGeneration(b, side: .left)?.battery == 50)
        #expect(JoyConDecoder.firstGeneration(b, side: .left)?.charging == true)
        b[0] = 0x21
        #expect(JoyConDecoder.firstGeneration(Array(b.prefix(15)), side: .left) != nil)
    }
    @Test func firstGenerationVoltageEstimateRequiresValidDischargingReply() {
        var reply = neutralFirst()
        reply[0] = 0x21
        reply[2] = 0x40
        reply[13] = 0xd0
        reply[14] = 0x50
        let cases: [(UInt16, Int?)] = [
            (0, nil), (1320, 1), (1376, 1), (1440, 11), (1501, 34),
            (1504, 36), (1560, 66), (1624, 100), (1680, 100)
        ]
        for (voltage, expected) in cases {
            reply[15] = UInt8(truncatingIfNeeded: voltage)
            reply[16] = UInt8(voltage >> 8)
            #expect(JoyConDecoder.firstGenerationBatteryEstimate(reply) == expected)
        }
        #expect(JoyConDecoder.firstGenerationBatteryEstimate(Array(reply.prefix(16))) == nil)
        reply[2] = 0x50
        #expect(JoyConDecoder.firstGenerationBatteryEstimate(reply) == nil)
        reply[2] = 0x40
        reply[13] = 0
        #expect(JoyConDecoder.firstGenerationBatteryEstimate(reply) == nil)
        reply[13] = 0xd0
        reply[14] = 0x30
        #expect(JoyConDecoder.firstGenerationBatteryEstimate(reply) == nil)
    }
    @Test func secondGenerationLeftBits() {
        var b = neutralSecond(); b[2] = 0xff; b[3] = 0xff
        let state = JoyConDecoder.secondGeneration(b, side: .left)
        #expect(state?.buttons == [.down, .right, .left, .up, .l, .zl, .minus, .leftStick, .capture, .gl, .leftSR, .leftSL])
        #expect(state?.stick == .neutral); #expect(state?.battery == 100)
    }
    @Test func secondGenerationRightBits() {
        var b = neutralSecond(); b[2] = 0xff; b[3] = 0xff; b[1] = 0x12
        let state = JoyConDecoder.secondGeneration(b, side: .right)
        #expect(state?.buttons == [.b, .a, .y, .x, .r, .zr, .plus, .rightStick, .home, .gr, .c, .rightSR, .rightSL])
        #expect(state?.battery == 50); #expect(state?.charging == true)
    }
    @Test func everyBitHasIndependentMeaning() {
        let maps: [(JoyConSide, Int, [ControllerInput?])] = [
            (.left, 2, [.down, .right, .left, .up, .l, .zl, .minus, .leftStick]),
            (.right, 2, [.b, .a, .y, .x, .r, .zr, .plus, .rightStick]),
            (.left, 3, [.capture, nil, .gl, nil, nil, nil, .leftSR, .leftSL]),
            (.right, 3, [.home, nil, .gr, nil, .c, nil, .rightSR, .rightSL]),
        ]
        for (side, offset, inputs) in maps {
            for (bit, input) in inputs.enumerated() {
                var b = neutralSecond(); b[offset] = 1 << bit
                #expect(JoyConDecoder.secondGeneration(b, side: side)?.buttons == Set(input.map { [$0] } ?? []))
            }
        }
    }
    @Test func rejectsMalformedFrames() {
        for length in 0..<49 { #expect(JoyConDecoder.firstGeneration(Array(neutralFirst().prefix(length)), side: .left) == nil) }
        for length in 0..<63 { #expect(JoyConDecoder.secondGeneration(Array(neutralSecond().prefix(length)), side: .right) == nil) }
        #expect(JoyConDecoder.secondGeneration(neutralSecond() + [0], side: .left) == nil)
        var b = neutralFirst(); b[0] = 0x3f
        #expect(JoyConDecoder.firstGeneration(b, side: .left) == nil)
    }
    @Test func stickNormalization() {
        #expect(StickPosition.neutral.normalized(deadzone: 0.18).x == 0)
        #expect(StickPosition(x: 2100, y: 2000).normalized(deadzone: 0.18).y == 0)
        #expect(StickPosition(x: 4095, y: 2048).normalized(deadzone: 0.18).x == 1)
        #expect(StickPosition(x: 0, y: 2048).normalized(deadzone: 0.18).x == -1)
        let diagonal = StickPosition(x: 4095, y: 4095).normalized(deadzone: 0.18)
        #expect(abs(hypot(diagonal.x, diagonal.y) - 1) < 0.001)
        #expect(StickPosition(x: 1800, y: 2200).normalized(center: .init(x: 1800, y: 2200), deadzone: 0.1).x == 0)
    }
    @Test func commandFraming() {
        #expect(ControllerCommand.ble(0xc, 2, [3, 0, 0, 0]).data == [0xc, 0x91, 1, 2, 0, 4, 0, 0, 3, 0, 0, 0])
        let hid = ControllerCommand.hid(3, payload: [0x30], counter: 17).data
        #expect(hid.count == 49); #expect(hid[0] == 1); #expect(hid[1] == 1)
        #expect(hid[10] == 3); #expect(hid[11] == 0x30)
        #expect(ControllerCommand.secondGenerationStartup.filter(\.waitForInput).count == 1)
    }
}

extension ProtocolTests {
    @Test func deviceInfoExtractsOnlyValidFirstGenerationAddress() {
        var report = neutralFirst()
        report[0] = 0x21
        report[13] = 0x82
        report[14] = 0x02
        #expect(JoyConDecoder.firstGenerationAddress(report) == nil)
        report[19..<25] = [0xA1, 0xB2, 0x05, 0xC3, 0xD4, 0xE5]
        #expect(JoyConDecoder.firstGenerationAddress(report) == "A1B205C3D4E5")
        #expect(JoyConDecoder.firstGenerationAddress(Array(report.prefix(24))) == nil)
        report[13] = 0
        #expect(JoyConDecoder.firstGenerationAddress(report) == nil)
    }
}
