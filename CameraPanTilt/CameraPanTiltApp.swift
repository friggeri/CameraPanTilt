import Foundation
import IOKit
import IOKit.hid
import IOKit.usb
import LaunchAtLogin
import OSLog
import SwiftUI
import USBDeviceSwift

let panTiltVendorId = 0x2E8A
let panTiltProductId = 0x101A

let joystickVendorId = 0x1D50
let wiredJoystickProductId = 0x615F
let wirelessJoystickProductId = 0x615F

extension HIDDevice {
    func isPanTilt() -> Bool {
        vendorId == panTiltVendorId && productId == panTiltProductId
    }

    func isJoystick() -> Bool {
        (vendorId == joystickVendorId) && (productId == wiredJoystickProductId || productId == wirelessJoystickProductId)
    }
}

let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "log")

@MainActor
class PanTilt: ObservableObject {
    let deviceMonitor = HIDDeviceMonitor([
        HIDDeviceMatcher(vendorId: joystickVendorId, productId: wiredJoystickProductId, usagePage: kHIDPage_GenericDesktop, usage: kHIDUsage_GD_Joystick),
        HIDDeviceMatcher(vendorId: joystickVendorId, productId: wirelessJoystickProductId, usagePage: kHIDPage_GenericDesktop, usage: kHIDUsage_GD_Joystick),
        HIDDeviceMatcher(vendorId: panTiltVendorId, productId: panTiltProductId),
    ])

    var panTiltDevice: HIDDevice? = nil

    @objc func usbConnected(notification: NSNotification) {
        guard let nobj = notification.object as? NSDictionary else {
            return
        }

        guard let device: HIDDevice = nobj["device"] as? HIDDevice else {
            return
        }

        if device.isPanTilt() {
            log.debug("Pan Tilt Connected")
            DispatchQueue.main.async {
                self.panTiltDevice = device
            }
        } else if device.isJoystick() {
            log.debug("Joystick Connected")
        }
    }

    @objc func usbDisconnected(notification: NSNotification) {
        guard let nobj = notification.object as? NSDictionary else {
            return
        }

        guard let device: HIDDevice = nobj["device"] as? HIDDevice else {
            return
        }
        if device.isPanTilt() {
            log.debug("Pan Tilt Disconnected")

            DispatchQueue.main.async {
                self.panTiltDevice = nil
            }
        } else if device.isJoystick() {
            log.debug("Joystick Disconnected")
        }
    }

    @objc func hidReadData(notification: Notification) {
        guard let obj = notification.object as? NSDictionary else {
            return
        }
        let data: [Int8] = (obj["data"] as! Data).map { Int8(bitPattern: $0) }
        let device = obj["device"] as! HIDDevice

        if !(device.isJoystick() && data[0] == 4) {
            return
        }

        guard let panTiltDevice = panTiltDevice else {
            return
        }
        panTiltDevice.sendReport(reportId: 5, payload: [UInt8(bitPattern: data[1]), UInt8(bitPattern: data[2])])
    }

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(usbConnected), name: .HIDDeviceConnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(usbDisconnected), name: .HIDDeviceDisconnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(hidReadData), name: .HIDDeviceDataReceived, object: nil)

        let deviceDaemon = Thread(target: deviceMonitor, selector: #selector(deviceMonitor.start), object: nil)
        log.debug("PanTilt Controller Starting")
        deviceDaemon.start()
    }
}

@main
struct CameraPanTiltApp: App {
    @StateObject var panTilt = PanTilt()

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
                 LaunchAtLogin.Toggle()
             }.padding()
         }
    }
}
