import UIKit
import WebKit
import CoreBluetooth

@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let win = UIWindow(frame: UIScreen.main.bounds)
        win.rootViewController = ControllerViewController()
        win.makeKeyAndVisible()
        window = win
        return true
    }
}

final class ControllerViewController: UIViewController, WKScriptMessageHandler {
    private var web: WKWebView!
    private var radio: RemoteCentral!

    override func viewDidLoad() {
        super.viewDidLoad()
        let config = WKWebViewConfiguration()
        let bridge = WKUserContentController()
        bridge.add(self, name: "vcremote")
        guard let bridgeURL = Bundle.main.url(forResource: "NativeBridge", withExtension: "js"),
              let bridgeCode = try? String(contentsOf: bridgeURL, encoding: .utf8) else {
            fatalError("Missing NativeBridge.js")
        }
        bridge.addUserScript(WKUserScript(source: bridgeCode, injectionTime: .atDocumentStart,
                                          forMainFrameOnly: true))
        config.userContentController = bridge
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            web.topAnchor.constraint(equalTo: view.topAnchor),
            web.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        self.web = web
        radio = RemoteCentral()
        radio.feedback = { [weak self] type, detail in self?.notifyPage(type, detail) }
        if let page = Bundle.main.url(forResource: "index", withExtension: "html") {
            web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
    }

    private func notifyPage(_ type: String, _ detail: String) {
        let data = try? JSONSerialization.data(withJSONObject: [type, detail])
        guard let data = data, let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.vcBLEEvent.apply(null, \(json));", completionHandler: nil)
    }

    func userContentController(_ control: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let data = message.body as? [String: Any],
              let type = data["type"] as? String else { return }
        switch type {
        case "connect": radio.connect(pin: data["pin"] as? String ?? "")
        case "packet": radio.controllerMessage(data["payload"] as? String ?? "")
        case "disconnect": radio.disconnect()
        default: break
        }
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
    func controllerMessage(_ value: String) {
        guard authorized, value.hasPrefix("G,") else { return }
        let parts = value.split(separator:",",omittingEmptySubsequences:false)
        guard parts.count == 5, let id = Int(parts[1]), (1...18).contains(id),
              let x = Double(parts[3]), let y = Double(parts[4]),
              x.isFinite, y.isFinite, abs(x) <= 1, abs(y) <= 1 else { return }
        let end = parts[2] == "e"
        guard end || parts[2] == "b" || parts[2] == "m" else {return}
        if id == 1 {axes[0] = end ? 0 : x;axes[1] = end ? 0 : y}
        else if id == 2 {axes[2] = end ? 0 : x;axes[3] = end ? 0 : y}
        else {
            let bit = UInt16(1) << UInt16(id-3)
            if end {mask &= ~bit} else {mask |= bit}
        }
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
