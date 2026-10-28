import UIKit

// Single source of truth for the 10-byte BLE protocol. IDs 3...18 map
// directly to bits 0...15 in the iPad receiver; analogs use IDs 1 and 2.
struct ControllerState: Equatable {
    var mask: UInt16 = 0
    var leftX: Double = 0
    var leftY: Double = 0
    var rightX: Double = 0
    var rightY: Double = 0

    mutating func setStick(_ id: Int, x: CGFloat, y: CGFloat) {
        let sx = Double(max(-1, min(1, x)))
        let sy = Double(max(-1, min(1, y)))
        if id == 1 { leftX = sx; leftY = sy }
        if id == 2 { rightX = sx; rightY = sy }
    }

    mutating func setButton(_ id: Int, down: Bool) {
        guard (3...18).contains(id) else { return }
        let bit = UInt16(1) << UInt16(id - 3)
        if down { mask |= bit } else { mask &= ~bit }
    }
}
