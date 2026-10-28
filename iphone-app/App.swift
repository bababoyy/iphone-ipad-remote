import UIKit
import CoreBluetooth

@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let win = UIWindow(frame: UIScreen.main.bounds)
        win.rootViewController = ControllerViewController()
        win.makeKeyAndVisible()
        window = win
        return true
    }
}

final class ControllerViewController: UIViewController {
    private let canvas = GamepadCanvas()
    private let topBar = UIView()
    private let statusLabel = UILabel()
    private let statusDot = UIView()
    private let pairButton = UIButton(type: .system)
    private let gearButton = UIButton(type: .system)
    private let pinField = UITextField()
    private let pairingMessage = UILabel()
    private var pairingOverlay = UIView()
    private var backdrop = CAGradientLayer()
    private var connected = false
    private var radio: RemoteCentral!
    private var sensitivity: CGFloat = 1
    private var haptics = true

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.039, green: 0.059, blue: 0.094, alpha: 1)
        backdrop.colors = [
            UIColor(red:0.047,green:0.071,blue:0.11,alpha:1).cgColor,
            UIColor(red:0.078,green:0.114,blue:0.172,alpha:1).cgColor
        ]
        backdrop.startPoint = CGPoint(x:0.3,y:0)
        backdrop.endPoint = CGPoint(x:0.7,y:1)
        view.layer.insertSublayer(backdrop,at:0)
        configureHeader()
        configureCanvas()
        configurePairing()
        sensitivity = CGFloat(UserDefaults.standard.double(forKey:"nativeSensitivity"))
        if sensitivity < 0.4 || sensitivity > 2 { sensitivity = 1 }
        haptics = !UserDefaults.standard.bool(forKey:"nativeHapticsDisabled")
        canvas.stickSensitivity = sensitivity
        canvas.hapticsEnabled = haptics
        radio = RemoteCentral()
        radio.feedback = { [weak self] event,message in
            DispatchQueue.main.async { self?.handleRadio(event,message:message) }
        }
        canvas.onChange = { [weak self] state in self?.radio?.updateController(state) }
        NotificationCenter.default.addObserver(self,selector:#selector(backgrounded),
            name:UIApplication.willResignActiveNotification,object:nil)
        showPairing()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdrop.frame = view.bounds
    }
    override var prefersStatusBarHidden: Bool { true }
    deinit { NotificationCenter.default.removeObserver(self) }
    private func configureHeader() {
        topBar.translatesAutoresizingMaskIntoConstraints=false
        view.addSubview(topBar)
        let logo=UILabel()
        logo.attributedText = NSAttributedString(string:"VCREMOTE / PAD",attributes:[
            .font:UIFont.monospacedSystemFont(ofSize:14,weight:.bold),
            .foregroundColor:UIColor(red:0.69,green:0.83,blue:0.99,alpha:1),
            .kern:1.1])
        logo.translatesAutoresizingMaskIntoConstraints=false
        topBar.addSubview(logo)
        statusDot.backgroundColor=UIColor(red:0.89,green:0.57,blue:0.46,alpha:1)
        statusDot.layer.cornerRadius=4
        statusDot.translatesAutoresizingMaskIntoConstraints=false
        topBar.addSubview(statusDot)
        statusLabel.text="Not connected"
        statusLabel.textColor=UIColor(red:0.64,green:0.73,blue:0.84,alpha:1)
        statusLabel.font=UIFont.systemFont(ofSize:11,weight:.medium)
        statusLabel.adjustsFontSizeToFitWidth=true
        statusLabel.minimumScaleFactor=0.75
        statusLabel.translatesAutoresizingMaskIntoConstraints=false
        topBar.addSubview(statusLabel)

        func button(_ b:UIButton,_ title:String) {
            b.setTitle(title,for:.normal)
            b.setTitleColor(.white,for:.normal)
            b.titleLabel?.font=UIFont.systemFont(ofSize:12,weight:.semibold)
            b.backgroundColor=UIColor(red:0.115,green:0.17,blue:0.25,alpha:1)
            b.layer.cornerRadius=10
            b.layer.borderWidth=1
            b.layer.borderColor=UIColor(red:0.27,green:0.37,blue:0.51,alpha:1).cgColor
            b.translatesAutoresizingMaskIntoConstraints=false
            topBar.addSubview(b)
        }
        button(pairButton,"Pair")
        button(gearButton,"⚙ Settings")
        pairButton.addTarget(self,action:#selector(openPairing),for:.touchUpInside)
        gearButton.addTarget(self,action:#selector(openSettings),for:.touchUpInside)
        let line=UIView()
        line.backgroundColor=UIColor(red:0.18,green:0.26,blue:0.37,alpha:1)
        line.translatesAutoresizingMaskIntoConstraints=false
        topBar.addSubview(line)
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant:48),
            logo.leadingAnchor.constraint(equalTo:topBar.leadingAnchor,constant:12),
            logo.centerYAnchor.constraint(equalTo:topBar.centerYAnchor),
            statusDot.leadingAnchor.constraint(equalTo:logo.trailingAnchor,constant:14),
            statusDot.centerYAnchor.constraint(equalTo:logo.centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant:8),
            statusDot.heightAnchor.constraint(equalToConstant:8),
            statusLabel.leadingAnchor.constraint(equalTo:statusDot.trailingAnchor,constant:7),
            statusLabel.centerYAnchor.constraint(equalTo:topBar.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo:pairButton.leadingAnchor,constant:-8),
            pairButton.trailingAnchor.constraint(equalTo:gearButton.leadingAnchor,constant:-7),
            pairButton.centerYAnchor.constraint(equalTo:topBar.centerYAnchor),
            pairButton.widthAnchor.constraint(equalToConstant:48),
            pairButton.heightAnchor.constraint(equalToConstant:33),
            gearButton.trailingAnchor.constraint(equalTo:topBar.trailingAnchor,constant:-9),
            gearButton.centerYAnchor.constraint(equalTo:topBar.centerYAnchor),
            gearButton.widthAnchor.constraint(equalToConstant:86),
            gearButton.heightAnchor.constraint(equalToConstant:33),
            line.leadingAnchor.constraint(equalTo:topBar.leadingAnchor),
            line.trailingAnchor.constraint(equalTo:topBar.trailingAnchor),
            line.bottomAnchor.constraint(equalTo:topBar.bottomAnchor),
            line.heightAnchor.constraint(equalToConstant:1)
        ])
    }
    private func configureCanvas() {
        canvas.translatesAutoresizingMaskIntoConstraints=false
        view.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo:topBar.bottomAnchor,constant:4),
            canvas.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func configurePairing() {
        pairingOverlay=UIView()
        pairingOverlay.backgroundColor=UIColor.black.withAlphaComponent(0.78)
        pairingOverlay.translatesAutoresizingMaskIntoConstraints=false
        view.addSubview(pairingOverlay)
        NSLayoutConstraint.activate([
            pairingOverlay.topAnchor.constraint(equalTo:view.topAnchor),
            pairingOverlay.bottomAnchor.constraint(equalTo:view.bottomAnchor),
            pairingOverlay.leadingAnchor.constraint(equalTo:view.leadingAnchor),
            pairingOverlay.trailingAnchor.constraint(equalTo:view.trailingAnchor)
        ])
        let panel=UIView()
        panel.backgroundColor=UIColor(red:0.085,green:0.13,blue:0.21,alpha:1)
        panel.layer.cornerRadius=19
        panel.layer.borderWidth=1
        panel.layer.borderColor=UIColor(red:0.31,green:0.42,blue:0.56,alpha:1).cgColor
        panel.translatesAutoresizingMaskIntoConstraints=false
        pairingOverlay.addSubview(panel)
        let heading=UILabel()
        heading.text="Connect to iPad"
        heading.textColor = .white
        heading.font = .systemFont(ofSize:20,weight:.bold)
        heading.translatesAutoresizingMaskIntoConstraints=false
        panel.addSubview(heading)
        let close=UIButton(type:.system)
        close.setTitle("×",for:.normal)
        close.setTitleColor(UIColor(red:0.83,green:0.90,blue:1,alpha:1),for:.normal)
        close.titleLabel?.font = .systemFont(ofSize:27,weight:.regular)
        close.addTarget(self,action:#selector(closePairing),for:.touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints=false
        panel.addSubview(close)
        let subtitle=UILabel()
        subtitle.text="Enter the 6-digit PIN shown on iPad."
        subtitle.textColor=UIColor(red:0.67,green:0.77,blue:0.88,alpha:1)
        subtitle.font = .systemFont(ofSize:13)
        subtitle.translatesAutoresizingMaskIntoConstraints=false
        panel.addSubview(subtitle)
        pinField.placeholder="000000"
        pinField.keyboardType = .numberPad
        pinField.textContentType = .oneTimeCode
        pinField.textAlignment = .center
        pinField.textColor = .white
        pinField.font = .monospacedDigitSystemFont(ofSize:21,weight:.semibold)
        pinField.backgroundColor=UIColor(red:0.06,green:0.09,blue:0.15,alpha:1)
        pinField.layer.cornerRadius=10
        pinField.layer.borderWidth=1
        pinField.layer.borderColor=UIColor(red:0.34,green:0.47,blue:0.64,alpha:1).cgColor
        pinField.translatesAutoresizingMaskIntoConstraints=false
        panel.addSubview(pinField)
        let connect=UIButton(type:.system)
        connect.setTitle("Connect",for:.normal)
        connect.setTitleColor(UIColor(red:0.05,green:0.09,blue:0.15,alpha:1),for:.normal)
        connect.backgroundColor=UIColor(red:0.51,green:0.73,blue:0.97,alpha:1)
        connect.titleLabel?.font = .systemFont(ofSize:14,weight:.bold)
        connect.layer.cornerRadius=10
        connect.addTarget(self,action:#selector(connectTapped),for:.touchUpInside)
        connect.translatesAutoresizingMaskIntoConstraints=false
        panel.addSubview(connect)
        pairingMessage.text="Bluetooth LE · No hotspot required"
        pairingMessage.numberOfLines=2
        pairingMessage.textAlignment = .center
        pairingMessage.textColor=UIColor(red:0.68,green:0.77,blue:0.86,alpha:1)
        pairingMessage.font = .systemFont(ofSize:11)
        pairingMessage.translatesAutoresizingMaskIntoConstraints=false
        panel.addSubview(pairingMessage)
        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo:pairingOverlay.centerXAnchor),
            panel.centerYAnchor.constraint(equalTo:pairingOverlay.centerYAnchor),
            panel.widthAnchor.constraint(equalToConstant:326),
            panel.heightAnchor.constraint(equalToConstant:227),
            heading.topAnchor.constraint(equalTo:panel.topAnchor,constant:20),
            heading.leadingAnchor.constraint(equalTo:panel.leadingAnchor,constant:19),
            close.topAnchor.constraint(equalTo:panel.topAnchor,constant:8),
            close.trailingAnchor.constraint(equalTo:panel.trailingAnchor,constant:-9),
            close.widthAnchor.constraint(equalToConstant:36),
            close.heightAnchor.constraint(equalToConstant:35),
            subtitle.topAnchor.constraint(equalTo:heading.bottomAnchor,constant:9),
            subtitle.leadingAnchor.constraint(equalTo:panel.leadingAnchor,constant:19),
            subtitle.trailingAnchor.constraint(equalTo:panel.trailingAnchor,constant:-15),
            pinField.topAnchor.constraint(equalTo:subtitle.bottomAnchor,constant:14),
            pinField.leadingAnchor.constraint(equalTo:panel.leadingAnchor,constant:19),
            pinField.widthAnchor.constraint(equalToConstant:159),
            pinField.heightAnchor.constraint(equalToConstant:44),
            connect.leadingAnchor.constraint(equalTo:pinField.trailingAnchor,constant:8),
            connect.trailingAnchor.constraint(equalTo:panel.trailingAnchor,constant:-19),
            connect.centerYAnchor.constraint(equalTo:pinField.centerYAnchor),
            connect.heightAnchor.constraint(equalTo:pinField.heightAnchor),
            pairingMessage.topAnchor.constraint(equalTo:pinField.bottomAnchor,constant:19),
            pairingMessage.leadingAnchor.constraint(equalTo:panel.leadingAnchor,constant:17),
            pairingMessage.trailingAnchor.constraint(equalTo:panel.trailingAnchor,constant:-17)
        ])
    }

    private func showPairing() {
        canvas.releaseAll()
        pairingOverlay.isHidden=false
        pairingMessage.text=connected ? "Connected. Close this window to play." :
            "Bluetooth LE · No hotspot required"
    }
    @objc private func openPairing() {showPairing()}
    @objc private func closePairing() {
        pinField.resignFirstResponder()
        pairingOverlay.isHidden=true
    }
    @objc private func connectTapped() {
        let pin=pinField.text?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
        guard pin.count==6,pin.allSatisfy({$0.isNumber}) else {
            pairingMessage.text="Please enter exactly six digits."
            return
        }
        pinField.resignFirstResponder()
        statusLabel.text="Searching for iPad…"
        pairingMessage.text="Looking for VCRemote via Bluetooth…"
        radio.connect(pin:pin)
    }
    private func handleRadio(_ event:String,message:String) {
        if event=="ready" {
            connected=true
            statusDot.backgroundColor=UIColor(red:0.55,green:0.85,blue:0.72,alpha:1)
            statusLabel.text="Bluetooth connected"
            pairingOverlay.isHidden=true
            pinField.resignFirstResponder()
        } else {
            connected=false
            canvas.releaseAll()
            statusDot.backgroundColor=UIColor(red:0.90,green:0.53,blue:0.46,alpha:1)
            statusLabel.text="Not connected"
            if event=="failure" {
                pairingMessage.text=message
                pairingOverlay.isHidden=false
            } else if event=="disconnected" {
                pairingMessage.text="Bluetooth disconnected. Reconnect with PIN."
                pairingOverlay.isHidden=false
            }
        }
    }
    @objc private func backgrounded() {canvas.releaseAll()}
    @objc private func openSettings() {
        canvas.releaseAll()
        let alert=UIAlertController(title:"Controller Settings",
            message:"Native UIKit · BLE input",preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"Stick sensitivity: 70%",style:.default){[weak self] _ in
            self?.setSensitivity(0.7)})
        alert.addAction(UIAlertAction(title:"Stick sensitivity: 100%",style:.default){[weak self] _ in
            self?.setSensitivity(1)})
        alert.addAction(UIAlertAction(title:"Stick sensitivity: 130%",style:.default){[weak self] _ in
            self?.setSensitivity(1.3)})
        alert.addAction(UIAlertAction(title:haptics ? "Disable haptics" : "Enable haptics",
                                      style:.default){[weak self] _ in self?.toggleHaptics()})
        alert.addAction(UIAlertAction(title:"Close",style:.cancel))
        present(alert,animated:true)
    }
    private func setSensitivity(_ value:CGFloat) {
        sensitivity=value;canvas.stickSensitivity=value
        UserDefaults.standard.set(Double(value),forKey:"nativeSensitivity")
    }
    private func toggleHaptics() {
        haptics.toggle();canvas.hapticsEnabled=haptics
        UserDefaults.standard.set(!haptics,forKey:"nativeHapticsDisabled")
    }
}

final class RemoteCentral: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private static let serviceID = CBUUID(string: "5CB83FF0-304B-4C67-87C9-0F2D12C31801")
    private static let authID = CBUUID(string: "5CB83FF0-304B-4C67-87C9-0F2D12C31802")
    private static let stateID = CBUUID(string: "5CB83FF0-304B-4C67-87C9-0F2D12C31803")
    var feedback: ((String, String) -> Void)?
    private var central: CBCentralManager!
    private var peer: CBPeripheral?
    private var stateCharacteristic: CBCharacteristic?
    private var pin: String?
    private var authorized = false
    private var scanNumber = 0
    private var timer: Timer?
    private var seq: UInt8 = 0
    private var mask: UInt16 = 0
    private var axes: [Double] = [0,0,0,0]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func connect(pin value: String) {
        guard value.utf8.count == 6, value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            feedback?("failure","PIN must contain six digits.")
            return
        }
        disconnect(notify: false)
        pin = value
        if central.state == .poweredOn { scan() }
        else if central.state != .unknown && central.state != .resetting {
            feedback?("failure","Turn Bluetooth on and grant access in Settings.")
        }
    }

    func disconnect() { disconnect(notify: true) }
    private func disconnect(notify: Bool) {
        scanNumber += 1
        central.stopScan()
        timer?.invalidate()
        timer = nil
        if let peer = peer { central.cancelPeripheralConnection(peer) }
        peer = nil
        pin = nil
        stateCharacteristic = nil
        authorized = false
        mask = 0
        axes = [0,0,0,0]
        if notify { feedback?("disconnected","") }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if pin != nil && peer == nil { scan() }
        } else if central.state == .poweredOff || central.state == .unauthorized || central.state == .unsupported {
            if pin != nil || authorized {
                disconnect(notify: false)
                feedback?("failure","Bluetooth is off or permission was denied.")
            }
        }
    }
    private func scan() {
        guard pin != nil, central.state == .poweredOn else { return }
        scanNumber += 1
        let id = scanNumber
        central.scanForPeripherals(withServices: [Self.serviceID],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey:false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self = self, self.scanNumber == id, self.peer == nil else { return }
            self.central.stopScan()
            self.pin = nil
            self.feedback?("failure","iPad not discovered. Open Vice City and allow Bluetooth.")
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String:Any], rssi RSSI: NSNumber) {
        guard peer == nil, pin != nil else { return }
        central.stopScan()
        peer = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.serviceID])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        fail("BLE connection failed.")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peer?.identifier == peripheral.identifier else { return }
        peer = nil
        timer?.invalidate(); timer = nil
        authorized = false
        mask = 0; axes = [0,0,0,0]
        if pin != nil { scan() } else { feedback?("disconnected","") }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: {$0.uuid == Self.serviceID}) else {
            fail("BLE service not available.");return
        }
        peripheral.discoverCharacteristics([Self.authID,Self.stateID],for:service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil,
              let auth = service.characteristics?.first(where:{$0.uuid == Self.authID}),
              let state = service.characteristics?.first(where:{$0.uuid == Self.stateID}),
              let pin = pin, let data = ("A"+pin).data(using:.utf8) else {
            fail("Invalid BLE characteristics.");return
        }
        stateCharacteristic = state
        peripheral.writeValue(data,for:auth,type:.withResponse)
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.authID else { return }
        guard error == nil else { fail("Wrong PIN or BLE authentication rejected.");return }
        authorized = true
        seq = 0
        feedback?("ready","Bluetooth connected")
        timer = Timer.scheduledTimer(withTimeInterval:1.0/30.0,repeats:true){[weak self] _ in
            self?.sendSnapshot()
        }
        if let timer = timer { RunLoop.main.add(timer,forMode:.common) }
        sendSnapshot()
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        // No backlog; next tick transmits the latest complete state.
    }
    private func fail(_ message: String) {
        disconnect(notify:false)
        feedback?("failure",message)
    }
    func updateController(_ controller: ControllerState) {
        // The CoreBluetooth transport owns only the latest complete state.
        // No individual touch events or WebSocket-style strings reach this layer.
        mask = controller.mask
        axes = [controller.leftX, controller.leftY,
                controller.rightX, controller.rightY]
    }
    private func sendSnapshot() {
        guard authorized, let peer = peer, let characteristic = stateCharacteristic,
              peer.state == .connected, peer.canSendWriteWithoutResponse,
              peer.maximumWriteValueLength(for:.withoutResponse) >= 10 else {return}
        func axisByte(_ v:Double)->UInt8 {
            let n = max(-127,min(127,Int((v*127).rounded())))
            return UInt8(bitPattern:Int8(n))
        }
        let bytes:[UInt8] = [1,seq,UInt8(truncatingIfNeeded:mask),
            UInt8(truncatingIfNeeded:mask >> 8),
            axisByte(axes[0]),axisByte(axes[1]),axisByte(axes[2]),axisByte(axes[3]),
            mask & (1 << 6) != 0 ? 255:0,mask & (1 << 7) != 0 ? 255:0]
        peer.writeValue(Data(bytes),for:characteristic,type:.withoutResponse)
        seq &+= 1
    }
}
