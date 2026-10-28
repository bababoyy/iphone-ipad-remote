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

    private func makeLayout() {
        let w = bounds.width, h = bounds.height
        guard w > 30 && h > 30 else { return }
        let portrait = h > w
        let shortSide = min(w,h)
        let stickR = min(67, shortSide * (portrait ? 0.13 : 0.185), w * 0.10)
        let faceR = min(25, max(16, shortSide * 0.067))
        let faceSpacing = faceR * 1.83
        let dR = min(23, max(16, shortSide * 0.062))
        let dStep = dR * 1.31
        let shoulderR = min(31, max(19, shortSide * 0.082))
        let landscape = !portrait
        let ls = CGPoint(x:w*(landscape ? 0.15 : 0.23),y:h*(landscape ? 0.44 : 0.29))
        let rs = CGPoint(x:w*(landscape ? 0.69 : 0.77),y:h*(landscape ? 0.70 : 0.29))
        let dc = CGPoint(x:w*(landscape ? 0.30 : 0.23),y:h*(landscape ? 0.75 : 0.70))
        let fc = CGPoint(x:w*(landscape ? 0.86 : 0.77),y:h*(landscape ? 0.38 : 0.70))
        let shoulderY = h*(landscape ? 0.085 : 0.085)
        func add(_ id:Int,_ title:String,_ x:CGFloat,_ y:CGFloat,_ radius:CGFloat,_ kind:Control.Kind) {
            controls.append(Control(id:id,title:title,center:CGPoint(x:x,y:y),radius:radius,kind:kind))
        }
        controls.removeAll(keepingCapacity:true)
        add(1,"L",ls.x,ls.y,stickR,.stick)
        add(2,"R",rs.x,rs.y,stickR,.stick)
        // Face diamond: Y/X/B/A -> matching GCController buttons.
        add(6,"Y",fc.x,fc.y-faceSpacing,faceR,.button)
        add(5,"X",fc.x-faceSpacing,fc.y,faceR,.button)
        add(4,"B",fc.x+faceSpacing,fc.y,faceR,.button)
        add(3,"A",fc.x,fc.y+faceSpacing,faceR,.button)
        add(11,"▲",dc.x,dc.y-dStep,dR,.directional)
        add(12,"▼",dc.x,dc.y+dStep,dR,.directional)
        add(13,"◀",dc.x-dStep,dc.y,dR,.directional)
        add(14,"▶",dc.x+dStep,dc.y,dR,.directional)
        let shoulders = [9,7,8,10]
        let titles = ["L2","L1","R1","R2"]
        let fractions: [CGFloat] = [0.075,0.20,0.80,0.925]
        for i in 0..<4 { add(shoulders[i],titles[i],w*fractions[i],shoulderY,shoulderR,.button) }
        let systemY = h*(landscape ? 0.54 : 0.51)
        add(16,"SELECT",w*0.43,systemY, min(31,shortSide*0.083),.button)
        add(15,"START",w*0.57,systemY, min(31,shortSide*0.083),.button)
        // Exposed L3/R3 buttons, independent of analog drag.
        add(17,"L3",ls.x+stickR*0.90,ls.y+stickR*0.88,faceR*0.76,.button)
        add(18,"R3",rs.x+stickR*0.90,rs.y+stickR*0.88,faceR*0.76,.button)
    }

    private func color(_ rgb: UInt32, alpha:CGFloat=1)->UIColor {
        UIColor(red:CGFloat((rgb>>16)&255)/255,green:CGFloat((rgb>>8)&255)/255,
                blue:CGFloat(rgb&255)/255,alpha:alpha)
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
        let dark=color(0x111a29)
        for c in controls {
            let held = contacts.values.contains { $0.id == c.id }
            let r=c.radius
            if c.kind == .stick {
                let outer=CGRect(x:c.center.x-r,y:c.center.y-r,width:r*2,height:r*2)
                ellipse(outer,fill:color(0x0e1725),stroke:color(0x455b78),line:2)
                ellipse(outer.insetBy(dx:r*0.17,dy:r*0.17),fill:color(0x142133),stroke:color(0x2a3d55),line:1)
                var x:CGFloat=0, y:CGFloat=0
                if let finger=contacts.values.first(where:{$0.id==c.id}) {
                    x=(finger.location.x-finger.origin.x)/r
                    y=(finger.location.y-finger.origin.y)/r
                    let length=max(1,sqrt(x*x+y*y));x/=length;y/=length
                }
                let kr=r*0.46
                let knob=CGRect(x:c.center.x+x*r*0.49-kr,y:c.center.y+y*r*0.49-kr,
                                width:kr*2,height:kr*2)
                ellipse(knob,fill:held ? color(0x496a91):color(0x324760),
                        stroke:color(0x7892b3),line:1.3)
                ellipse(knob.insetBy(dx:kr*0.38,dy:kr*0.38),fill:color(0x354b65),stroke:color(0x597493))
                label(c.id==1 ? "LEFT STICK" : "RIGHT STICK",
                      at:CGPoint(x:c.center.x,y:c.center.y+r+13),
                      size:9,color:color(0x8597b0),weight:.semibold)
                continue
            }
            let compact=c.id>=3 && c.id<=6
            let directional=c.kind == .directional
            let rect=CGRect(x:c.center.x-r,y:c.center.y-r,width:2*r,height:2*r)
            var fill=held ? color(0x557ca7) : dark
            var fg=color(0xd9e4f3)
            if compact {
                let palette:[UInt32]=[0x224762,0x4e3138,0x25483c,0x50432e]
                fill=held ? color(0x537fa8) : color(palette[c.id-3])
                fg=color([0xb2ddff,0xffb8c0,0xa3f2ce,0xffdc96][c.id-3])
            } else if directional {fill=held ? color(0x4b799d) : color(0x26374b)}
            if c.id>=7 && c.id<=10 {
                let wider=CGRect(x:c.center.x-r*1.39,y:c.center.y-r*0.56,
                                 width:r*2.78,height:r*1.12)
                roundRect(wider,radius:r*0.49,fill:fill,stroke:color(0x526681),line:1)
            } else if c.id==15 || c.id==16 {
                let wider=CGRect(x:c.center.x-r*1.35,y:c.center.y-r*0.60,
                                 width:r*2.7,height:r*1.2)
                roundRect(wider,radius:r*0.55,fill:fill,stroke:color(0x526681),line:1)
            } else if compact || c.id>=17 {
                ellipse(rect,fill:fill,stroke:color(0x63758e),line:1.2)
            } else {
                roundRect(rect,radius:r*0.23,fill:fill,stroke:color(0x6a7f97),line:1.2)
            }
            label(c.title,at:c.center,size:compact ? r*0.77 :
                    (c.id==15 || c.id==16 ? r*0.35 : r*0.58),color:fg)
        }
    }

    private func identify(_ point:CGPoint)->Control? {
        // Prefer smaller action buttons over the large analog hit region.
        let matching=controls.filter { c in
            let dx=point.x-c.center.x,dy=point.y-c.center.y
            let extra=c.kind == .button ? 8.0 : (c.kind == .stick ? 6.0 : 11.0)
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
                if abs(dx)>.8 {
                    state.setButton(dx>0 ? 14 : 13,down:true)
                }
                if abs(dy)>.8 {
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
