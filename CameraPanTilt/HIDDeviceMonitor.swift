import Cocoa
import Foundation
import IOKit.hid

public extension Notification.Name {
    static let HIDDeviceDataReceived = Notification.Name("HIDDeviceDataReceived")
    static let HIDDeviceConnected = Notification.Name("HIDDeviceConnected")
    static let HIDDeviceDisconnected = Notification.Name("HIDDeviceDisconnected")
}

public class HIDDevice {
    public let id:Int32
    public let vendorId:Int
    public let productId:Int
    public let reportSize:Int
    public let device:IOHIDDevice
    public let name:String
    
    public init(device:IOHIDDevice) {
        self.device = device
        
        self.id = IOHIDDeviceGetProperty(self.device, kIOHIDLocationIDKey as CFString) as? Int32 ?? 0
        self.name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
        self.vendorId = IOHIDDeviceGetProperty(self.device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        self.productId = IOHIDDeviceGetProperty(self.device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        self.reportSize = IOHIDDeviceGetProperty(self.device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 0
    }
    
    public func sendReport(reportId: UInt8, payload: [UInt8]) {
        var bytesArray: [UInt8] = payload
        bytesArray.insert(reportId, at: 0)

        if bytesArray.count > reportSize {
            print("Output data too large for USB report")
            return
        }
        
        Data(bytesArray).withUnsafeBytes { unsafeBytes in
            let bytes = unsafeBytes.bindMemory(to: UInt8.self).baseAddress!
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                CFIndex(0),
                bytes,
                unsafeBytes.count
            )
        }
    }
}

public struct HIDDeviceMatcher {
    public let vendorId:Int
    public let productId:Int
    public var usagePage:Int?
    public var usage:Int?

    public init (vendorId:Int, productId:Int) {
        self.vendorId = vendorId
        self.productId = productId
    }

    public init (vendorId:Int, productId:Int, usagePage:Int?, usage:Int?) {
        self.vendorId = vendorId
        self.productId = productId
        self.usagePage = usagePage
        self.usage = usage
    }
    
    public func toDictionary() -> [String:Any] {
        var match = [kIOHIDProductIDKey: productId, kIOHIDVendorIDKey: vendorId]
        if let usagePage = usagePage {
            match[kIOHIDDeviceUsagePageKey] = usagePage
        }
        if let usage = usage {
            match[kIOHIDDeviceUsageKey] = usage
        }
        return match
    }
}

open class HIDDeviceMonitor {
    public let matchers:[HIDDeviceMatcher]
    
    public init(_ matchers:[HIDDeviceMatcher]) {
        self.matchers = matchers
    }
    
    @objc open func start() {
        let managerRef = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(managerRef, self.matchers.map({m in m.toDictionary()}) as CFArray)
        IOHIDManagerScheduleWithRunLoop(managerRef, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue);
        IOHIDManagerOpen(managerRef, IOOptionBits(kIOHIDOptionsTypeNone));
        
        let matchingCallback:IOHIDDeviceCallback = { inContext, inResult, inSender, inIOHIDDeviceRef in
            let this:HIDDeviceMonitor = unsafeBitCast(inContext, to: HIDDeviceMonitor.self)
            this.rawDeviceAdded(inResult, inSender: inSender!, inIOHIDDeviceRef: inIOHIDDeviceRef)
        }
        
        let removalCallback:IOHIDDeviceCallback = { inContext, inResult, inSender, inIOHIDDeviceRef in
            let this:HIDDeviceMonitor = unsafeBitCast(inContext, to: HIDDeviceMonitor.self)
            this.rawDeviceRemoved(inResult, inSender: inSender!, inIOHIDDeviceRef: inIOHIDDeviceRef)
            
        }
        IOHIDManagerRegisterDeviceMatchingCallback(managerRef, matchingCallback, unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
        IOHIDManagerRegisterDeviceRemovalCallback(managerRef, removalCallback, unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
        
        RunLoop.current.run()
    }
    
    open func rawDeviceAdded(_ inResult: IOReturn, inSender: UnsafeMutableRawPointer, inIOHIDDeviceRef: IOHIDDevice!) {
        let device = HIDDevice(device:inIOHIDDeviceRef)
        let reportSize = device.reportSize
        let report = UnsafeMutablePointer<UInt8>.allocate(capacity: device.reportSize)
        
        let inputCallback : IOHIDReportCallback = { inContext, inResult, inSender, type, reportId, report, reportLength in
            print("here")
            guard let inContext = inContext else {
                return
            }
            let device = Unmanaged<HIDDevice>.fromOpaque(inContext).takeUnretainedValue()
            
            let data = Data(bytes: UnsafePointer<UInt8>(report), count: reportLength)
            NotificationCenter.default.post(name: .HIDDeviceDataReceived, object: ["data": data, "device": device])
           
        }
        
        let context = Unmanaged.passRetained(device).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(inIOHIDDeviceRef!, report, reportSize, inputCallback, context)
        
        NotificationCenter.default.post(name: .HIDDeviceConnected, object: ["device": device])
    }
    
    open func rawDeviceRemoved(_ inResult: IOReturn, inSender: UnsafeMutableRawPointer, inIOHIDDeviceRef: IOHIDDevice!) {
        let device = HIDDevice(device:inIOHIDDeviceRef)
        NotificationCenter.default.post(name: .HIDDeviceDisconnected, object: [
            "device": device
        ])
    }
}
