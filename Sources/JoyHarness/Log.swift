import os

enum Log {
    static let app = Logger(subsystem: "vip.tokenzz.joyharness", category: "app")
    static let hid = Logger(subsystem: "vip.tokenzz.joyharness", category: "hid")
    static let bluetooth = Logger(subsystem: "vip.tokenzz.joyharness", category: "bluetooth")
    static let settings = Logger(subsystem: "vip.tokenzz.joyharness", category: "settings")
}
