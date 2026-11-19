import Foundation

/// A physical selection survives disconnects; another controller never takes over.
struct ControllerSelection: Codable, Equatable {
    private(set) var deviceID: String?
    private(set) var profileID: String?

    var profile: JoyConProfile? { JoyConProfile.all.first { $0.id == profileID } }

    mutating func select(_ device: ConnectedJoyCon) {
        deviceID = device.id
        profileID = device.profile.id
    }

    mutating func selectProfile(_ profile: JoyConProfile) {
        deviceID = nil
        profileID = profile.id
    }

    /// Bind only the first ready device when no physical device has been chosen.
    @discardableResult
    mutating func discover(_ device: ConnectedJoyCon) -> Bool {
        guard deviceID == nil, device.ready, profileID == nil || profileID == device.profile.id else { return false }
        select(device)
        return true
    }
}

extension ConnectedJoyCon {
    // Both BLE UUIDs and HID serial/registry identities distinguish equal models.
    var identitySuffix: String { String(id.suffix(6)).uppercased() }
}
