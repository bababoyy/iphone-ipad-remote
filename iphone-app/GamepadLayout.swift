import Foundation

/// Decoded iphone-app/layout.json (embedded as kGamepadLayoutJSON by
/// scripts/embed_layout.py). Sizes are resolved exactly like
/// scripts/gamepad_layout.py so the SVG preview matches the app.
struct GamepadLayoutSpec: Decodable {
    struct Chrome: Decodable {
        let headerHeight: Double
        let headerGap: Double
    }
    struct HitSlop: Decodable {
        let stick: Double
        let button: Double
        let directional: Double
    }
    struct Oriented<T: Decodable>: Decodable {
        let landscape: T
        let portrait: T
        func pick(portrait isPortrait: Bool) -> T { isPortrait ? portrait : landscape }
    }
    struct SizeRule: Decodable {
        let short: Double
        let min: Double?
        let max: Double?
        let maxWidth: Double?
    }
    struct Shape: Decodable {
        let type: String          // "circle" or "rect"
        let halfWidth: Double?    // rect: multiples of the control radius
        let halfHeight: Double?
        let corner: Double?
    }
    struct Style: Decodable {
        let shape: Shape
        let fill: String
        let heldFill: String
        let fg: String
        let stroke: String
        let strokeWidth: Double
        let labelScale: Double
    }
    struct StickStyle: Decodable {
        let base: String
        let baseStroke: String
        let ring: String
        let ringStroke: String
        let knob: String
        let knobHeld: String
        let knobStroke: String
        let cap: String
        let capStroke: String
        let caption: String
    }
    struct ControlSpec: Decodable {
        let id: Int
        let title: String
        let kind: String          // "stick", "button" or "directional"
        let size: String
        let radiusScale: Double?
        let group: String?
        let at: Oriented<[Double]>?
        let offset: [Double]?
        let offsetUnit: String?
        let style: String?
        let caption: String?
    }

    let version: Int
    let chrome: Chrome
    let hitSlop: HitSlop
    let sizes: [String: Oriented<SizeRule>]
    let groups: [String: Oriented<[Double]>]
    let stick: StickStyle
    let styles: [String: Style]
    let controls: [ControlSpec]

    /// The layout is validated in CI (scripts/gamepad_layout.py), so a decode
    /// failure here means the build embedded a broken file: fail loudly.
    static let shared: GamepadLayoutSpec = {
        do {
            return try JSONDecoder().decode(GamepadLayoutSpec.self, from: Data(kGamepadLayoutJSON.utf8))
        } catch {
            fatalError("Embedded layout.json is invalid: \(error)")
        }
    }()

    /// Scale by the short side, then clamp: min, max, maxWidth (same order as Python).
    func radius(_ rule: SizeRule, short: Double, width: Double) -> Double {
        var r = short * rule.short
        if let lo = rule.min { r = Swift.max(r, lo) }
        if let hi = rule.max { r = Swift.min(r, hi) }
        if let fraction = rule.maxWidth { r = Swift.min(r, width * fraction) }
        return r
    }

    /// Named radii for a canvas size, e.g. ["stick": 60.9, "face": 22.0, ...].
    func resolvedSizes(width: Double, height: Double) -> [String: Double] {
        let isPortrait = height > width
        let short = Swift.min(width, height)
        var out: [String: Double] = [:]
        for (name, rule) in sizes {
            out[name] = radius(rule.pick(portrait: isPortrait), short: short, width: width)
        }
        return out
    }

    /// Center point of a control for a canvas size.
    func center(of control: ControlSpec, width: Double, height: Double,
                sizes resolved: [String: Double]) -> (x: Double, y: Double) {
        let isPortrait = height > width
        var fraction = [0.5, 0.5]
        if let name = control.group, let point = groups[name] {
            fraction = point.pick(portrait: isPortrait)
        } else if let point = control.at {
            fraction = point.pick(portrait: isPortrait)
        }
        var x = width * fraction[0]
        var y = height * fraction[1]
        if let offset = control.offset, offset.count == 2,
           let unitName = control.offsetUnit, let unit = resolved[unitName] {
            x += offset[0] * unit
            y += offset[1] * unit
        }
        return (x, y)
    }
}
