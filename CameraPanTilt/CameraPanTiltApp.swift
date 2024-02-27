import Defaults
import GameController
import KeyboardShortcuts
import SwiftUI
import USBDeviceSwift
import Foundation
import IOKit
import IOKit.usb
import IOKit.hid

let vendorId = 0x2E8A
let productId = 0x101A

let joystickVendorId = 0x1d50
let joystickProductId = 0x615f

extension KeyboardShortcuts.Name {
    static let moveLeft = Self("moveLeft")
    static let moveRight = Self("moveRight")
    static let moveUp = Self("moveUp")
    static let moveDown = Self("moveDown")
}

extension Defaults.Keys {
    static let enableKeyMovement = Key<Bool>("enableKeyMovement", default: false)
}

extension Data {
    var array: [UInt8] { Array(self) }

    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }

    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
        return map { String(format: format, $0) }.joined()
    }
}

extension Numeric {
    var data: Data {
        var source = self
        return Data(bytes: &source, count: MemoryLayout<Self>.size)
    }
}

@MainActor
class PanTilt: ObservableObject {
    let deviceMonitor = HIDDeviceMonitor([
        HIDMonitorData(vendorId: vendorId, productId: productId),
    ], reportSize: 3)
    let joystickDeviceMonitor = HIDDeviceMonitor([
        HIDMonitorData(vendorId: joystickVendorId, productId: joystickProductId)
    ], reportSize: 64)
    var deviceInfo: HIDDevice? = nil

    @Published var isConnected = false
    @Published var panSpeed: Int8 = 0
    @Published var tiltSpeed: Int8 = 0

    private func sendReport(reportId: UInt8, payload: UInt16) {
        sendReport(reportId: reportId, payload: payload.bigEndian.data.array)
    }

    private func sendReport(reportId: UInt8, payload: [UInt8]) {
        return;
        if !isConnected || deviceInfo == nil {
            print("USB device is not connected")
            return
        }

        var bytesArray: [UInt8] = payload
        bytesArray.insert(reportId, at: 0)

        if bytesArray.count > deviceInfo!.reportSize {
            print("Output data too large for USB report")
            return
        }

        Data(bytesArray).withUnsafeBytes { unsafeBytes in
            let bytes = unsafeBytes.bindMemory(to: UInt8.self).baseAddress!
            IOHIDDeviceSetReport(
                deviceInfo!.device,
                kIOHIDReportTypeOutput,
                CFIndex(0),
                bytes,
                unsafeBytes.count
            )
        }
    }

    func setPan(position: UInt16) {
        sendReport(reportId: 3, payload: position)
    }

    func setTilt(position: UInt16) {
        sendReport(reportId: 4, payload: position)
    }

    func move(panSpeed: Int8, tiltSpeed: Int8) {
        sendReport(reportId: 5, payload: [UInt8(bitPattern: panSpeed), UInt8(bitPattern: tiltSpeed)])
    }

    @objc func usbConnected(notification: NSNotification) {
        guard let nobj = notification.object as? NSDictionary else {
            return
        }

        guard let deviceInfo: HIDDevice = nobj["device"] as? HIDDevice else {
            return
        }

        print("connected", deviceInfo, deviceInfo.reportSize)

        DispatchQueue.main.async {
            self.isConnected = true
            self.deviceInfo = deviceInfo
            self.sendReport(reportId: 4, payload: [9, 10])
        }
    }

    @objc func usbDisconnected(notification: NSNotification) {
        print(notification)
        guard let nobj = notification.object as? NSDictionary else {
            return
        }

        guard let id: String = nobj["id"] as? String else {
            return
        }
        print("disconnected %@", id)

        DispatchQueue.main.async {
            self.isConnected = false
            self.deviceInfo = nil
        }
    }

    @objc func hidReadData(notification: Notification) {
        if let obj = notification.object as? NSDictionary {
            // let data = obj["data"] as! Data
            print(obj)
            // print(data.count, data.hexEncodedString())
        }
    }

    @objc func controllerConnected(_ notification: NSNotification) {
        print("notification", notification)
        if let controller = notification.object as? GCController {
            print("controller connected", controller.vendorName!)
            if let thumbstick = controller.extendedGamepad?.rightThumbstick {
                thumbstick.valueChangedHandler = { _, xPos, yPos in
                    self.move(panSpeed: Int8(127 * xPos), tiltSpeed: Int8(127 * yPos))
                }
            }
        }
    }

    init() {
        print("starting")
        let deviceDaemon = Thread(target: deviceMonitor, selector: #selector(deviceMonitor.start), object: nil)
        let joystickDeviceDaemon = Thread(target: self.joystickDeviceMonitor, selector:#selector(self.joystickDeviceMonitor.start), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(usbConnected), name: .HIDDeviceConnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(usbDisconnected), name: .HIDDeviceDisconnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(hidReadData), name: .HIDDeviceDataReceived, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerConnected(_:)), name: .GCControllerDidConnect, object: nil)
        GCController.shouldMonitorBackgroundEvents = true
        
        let dict = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Joystick
        ] as NSDictionary

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone) )
        IOHIDManagerSetDeviceMatching(manager, dict.mutableCopy() as! NSMutableDictionary)
        
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>
        if let joystick = devices?.first {
            print("joystick", joystick)
            print("supported", GCController.supportsHIDDevice(joystick))
        }


        print("all registered")
        
        joystickDeviceDaemon.start()
        deviceDaemon.start()

        for (shortcut, (setPanTiltSpeed, clearPanTiltSpeed)) in [
            KeyboardShortcuts.Name.moveDown: (set: { [self] in self.tiltSpeed = -127 }, clear: { [self] in self.tiltSpeed = 0 }),
            KeyboardShortcuts.Name.moveUp: (set: { [self] in self.tiltSpeed = 127 }, clear: { [self] in self.tiltSpeed = 0 }),
            KeyboardShortcuts.Name.moveLeft: (set: { [self] in self.panSpeed = -127 }, clear: { [self] in self.panSpeed = 0 }),
            KeyboardShortcuts.Name.moveRight: (set: { [self] in self.panSpeed = 127 }, clear: { [self] in self.panSpeed = 0 }),
        ] {
            KeyboardShortcuts.onKeyDown(for: shortcut) {
                print("key down", shortcut)
                setPanTiltSpeed()
                self.move(panSpeed: self.panSpeed, tiltSpeed: self.tiltSpeed)
            }
            KeyboardShortcuts.onKeyUp(for: shortcut) {
                print("key up", shortcut)
                clearPanTiltSpeed()
                self.move(panSpeed: self.panSpeed, tiltSpeed: self.tiltSpeed)
            }
        }

        Task {
            for await value in Defaults.updates(.enableKeyMovement) {
                KeyboardShortcuts.isEnabled = value
            }
        }
    }
}

@main
struct CameraPanTiltApp: App {
    @StateObject var panTilt = PanTilt()
    @Default(.enableKeyMovement) var enableKeyMovement

    var body: some Scene {
        MenuBarExtra(
            "Pan Tilt",
            systemImage: "camera"
        ) {
            SettingsLink {
                Text("Settings")
            }
            Divider()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("Q")
        }
        Settings {
            Group {
                Defaults.Toggle("Enable Key Movement", key: .enableKeyMovement).onChange {
                    if !$0 {
                        KeyboardShortcuts.reset(
                            .moveLeft,
                            .moveRight,
                            .moveUp,
                            .moveDown
                        )
                    }
                }.padding(.bottom)
                Form {
                    KeyboardShortcuts.Recorder("Move Left:", name: .moveLeft)
                    KeyboardShortcuts.Recorder("Move Right:", name: .moveRight)
                    KeyboardShortcuts.Recorder("Move Up:", name: .moveUp)
                    KeyboardShortcuts.Recorder("Move Down:", name: .moveDown)
                }.disabled(!enableKeyMovement)
            }.padding()
        }
    }
}
