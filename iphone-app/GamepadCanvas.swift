import UIKit

/// One native touch surface, not a collection of competing gesture recognizers.
/// A finger owns its control for the lifetime of the touch. Every update
/// rebuilds one full controller snapshot; simultaneous fingers do not interfere.
final class GamepadCanvas: UIView {
    var onChange: ((ControllerState) -> Void)?
    var hapticsEnabled = true
    var stickSensitivity: CGFloat = 1
    private var lastState = ControllerState()
    private let haptic = UIImpactFeedbackGenerator(style: .soft)

    private struct Control {
        let id: Int
        let title: String
        let center: CGPoint
        let radius: CGFloat
        let kind: Kind
        let style: GamepadLayoutSpec.Style?   // nil for sticks
        let caption: String
        enum Kind { case stick, button, directional }
    }
    private struct Contact {
        let id: Int
        let kind: Control.Kind
        let origin: CGPoint
        let radius: CGFloat
        var location: CGPoint
    }
    private var contacts: [ObjectIdentifier: Contact] = [:]
    private var controls: [Control] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        contentMode = .redraw
        accessibilityLabel = "Native multitouch gamepad"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        makeLayout()
        setNeedsDisplay()
    }

    /// Positions and sizes come from iphone-app/layout.json (GamepadLayoutSpec);
    /// preview the same layout on a computer with scripts/render_layout_svg.py.
    private func makeLayout() {
        let w = bounds.width, h = bounds.height
        guard w > 30 && h > 30 else { return }
        let spec = GamepadLayoutSpec.shared
        let width = Double(w), height = Double(h)
        let sizes = spec.resolvedSizes(width: width, height: height)
        controls.removeAll(keepingCapacity:true)
        // Array order in layout.json is draw order and touch priority.
        for c in spec.controls {
            let p = spec.center(of: c, width: width, height: height, sizes: sizes)
            let radius = (sizes[c.size] ?? 20) * (c.radiusScale ?? 1)
            let kind: Control.Kind = c.kind == "stick" ? .stick :
                (c.kind == "directional" ? .directional : .button)
            let style = c.style.flatMap { spec.styles[$0] }
            controls.append(Control(id:c.id,title:c.title,center:CGPoint(x:p.x,y:p.y),
                                    radius:CGFloat(radius),kind:kind,style:style,
                                    caption:c.caption ?? ""))
        }
    }

    private func color(_ rgb: UInt32, alpha:CGFloat=1)->UIColor {
        UIColor(red:CGFloat((rgb>>16)&255)/255,green:CGFloat((rgb>>8)&255)/255,
                blue:CGFloat(rgb&255)/255,alpha:alpha)
    }
    /// "#rrggbb" from layout.json.
    private func color(_ hex: String)->UIColor {
        color(UInt32(String(hex.dropFirst()), radix:16) ?? 0xff00ff)
    }
    private func ellipse(_ rect:CGRect, fill:UIColor, stroke:UIColor?=nil, line:CGFloat=1) {
        let p=UIBezierPath(ovalIn:rect);fill.setFill();p.fill()
        if let stroke=stroke {stroke.setStroke();p.lineWidth=line;p.stroke()}
    }
    private func roundRect(_ rect:CGRect, radius:CGFloat, fill:UIColor, stroke:UIColor?=nil, line:CGFloat=1) {
        let p=UIBezierPath(roundedRect:rect,cornerRadius:radius)
        fill.setFill();p.fill()
        if let stroke=stroke {stroke.setStroke();p.lineWidth=line;p.stroke()}
    }
    private func label(_ title:String,at center:CGPoint,size:CGFloat,color:UIColor,weight:UIFont.Weight = .bold) {
        let f=UIFont.systemFont(ofSize:size,weight:weight)
        let attr:[NSAttributedString.Key:Any]=[.font:f,.foregroundColor:color]
        let text=title as NSString
        let dims=text.size(withAttributes:attr)
        text.draw(at:CGPoint(x:center.x-dims.width/2,y:center.y-dims.height/2),withAttributes:attr)
    }
    override func draw(_ rect:CGRect) {
        super.draw(rect)
        let st=GamepadLayoutSpec.shared.stick
        for c in controls {
            let held = contacts.values.contains { $0.id == c.id }
            let r=c.radius
            if c.kind == .stick {
                let outer=CGRect(x:c.center.x-r,y:c.center.y-r,width:r*2,height:r*2)
                ellipse(outer,fill:color(st.base),stroke:color(st.baseStroke),line:2)
                ellipse(outer.insetBy(dx:r*0.17,dy:r*0.17),fill:color(st.ring),stroke:color(st.ringStroke),line:1)
                var x:CGFloat=0, y:CGFloat=0
                if let finger=contacts.values.first(where:{$0.id==c.id}) {
                    x=(finger.location.x-finger.origin.x)/r
                    y=(finger.location.y-finger.origin.y)/r
                    let length=max(1,sqrt(x*x+y*y));x/=length;y/=length
                }
                let kr=r*0.46
                let knob=CGRect(x:c.center.x+x*r*0.49-kr,y:c.center.y+y*r*0.49-kr,
                                width:kr*2,height:kr*2)
                ellipse(knob,fill:color(held ? st.knobHeld : st.knob),
                        stroke:color(st.knobStroke),line:1.3)
                ellipse(knob.insetBy(dx:kr*0.38,dy:kr*0.38),fill:color(st.cap),stroke:color(st.capStroke))
                label(c.caption,at:CGPoint(x:c.center.x,y:c.center.y+r+13),
                      size:9,color:color(st.caption),weight:.semibold)
                continue
            }
            guard let style=c.style else {continue}
            let fill=color(held ? style.heldFill : style.fill)
            let stroke=color(style.stroke)
            let line=CGFloat(style.strokeWidth)
            if style.shape.type == "rect" {
                let hw=r*CGFloat(style.shape.halfWidth ?? 1)
                let hh=r*CGFloat(style.shape.halfHeight ?? 1)
                roundRect(CGRect(x:c.center.x-hw,y:c.center.y-hh,width:hw*2,height:hh*2),
                          radius:r*CGFloat(style.shape.corner ?? 0),fill:fill,stroke:stroke,line:line)
            } else {
                ellipse(CGRect(x:c.center.x-r,y:c.center.y-r,width:2*r,height:2*r),
                        fill:fill,stroke:stroke,line:line)
            }
            label(c.title,at:c.center,size:r*CGFloat(style.labelScale),color:color(style.fg))
        }
    }

    private func identify(_ point:CGPoint)->Control? {
        // Prefer smaller action buttons over the large analog hit region.
        let matching=controls.filter { c in
            let dx=point.x-c.center.x,dy=point.y-c.center.y
            let slop=GamepadLayoutSpec.shared.hitSlop
            let extra=CGFloat(c.kind == .button ? slop.button : (c.kind == .stick ? slop.stick : slop.directional))
            return hypot(dx,dy) <= c.radius+extra
        }
        return matching.min(by:{$0.radius<$1.radius})
    }
    private func updateState() {
        var state=ControllerState()
        // An arbitrary number of fingers can press one key without prematurely releasing it.
        for finger in contacts.values {
            switch finger.kind {
            case .stick:
                let dx=(finger.location.x-finger.origin.x)/max(1,finger.radius)
                let dy=(finger.location.y-finger.origin.y)/max(1,finger.radius)
                let magnitude=max(1,hypot(dx,dy))
                let x=max(-1,min(1,(dx/magnitude)*stickSensitivity))
                let y=max(-1,min(1,(-dy/magnitude)*stickSensitivity))
                state.setStick(finger.id,x:x,y:y)
            case .button:
                state.setButton(finger.id,down:true)
            case .directional:
                // Map the contact's displacement within the D-pad to cardinal bits.
                let dx=(finger.location.x-finger.origin.x)/max(1,finger.radius)
                let dy=(finger.location.y-finger.origin.y)/max(1,finger.radius)
                // Each direction button has an origin offset; retain its original key
                // and allow deliberate diagonal slides into adjacent directions.
                state.setButton(finger.id,down:true)
                if abs(dx) > 0.8 {
                    state.setButton(dx>0 ? 14 : 13,down:true)
                }
                if abs(dy) > 0.8 {
                    state.setButton(dy>0 ? 12 : 11,down:true)
                }
            }
        }
        if state != lastState {
            lastState=state
            onChange?(state)
            setNeedsDisplay()
        }
    }
    private func take(_ touches:Set<UITouch>,new:Bool) {
        for touch in touches {
            let key=ObjectIdentifier(touch)
            let p=touch.location(in:self)
            if new {
                guard let c=identify(p) else {continue}
                // Do not allow a second finger to take over a stick.
                if c.kind == .stick && contacts.values.contains(where:{$0.id==c.id}) {continue}
                contacts[key]=Contact(id:c.id,kind:c.kind,origin:c.center,radius:c.radius,location:p)
                if hapticsEnabled && c.kind != .stick {haptic.impactOccurred(intensity:0.6)}
            } else if var contact=contacts[key] {
                contact.location=p
                contacts[key]=contact
            }
        }
        updateState()
    }
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?) {take(touches,new:true)}
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent?) {take(touches,new:false)}
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?) {
        for touch in touches {contacts.removeValue(forKey:ObjectIdentifier(touch))}
        updateState()
    }
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent?) {
        for touch in touches {contacts.removeValue(forKey:ObjectIdentifier(touch))}
        updateState()
    }
    func releaseAll() {
        contacts.removeAll()
        lastState=ControllerState()
        onChange?(lastState)
        setNeedsDisplay()
    }
}
