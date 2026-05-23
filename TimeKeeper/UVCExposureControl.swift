import Foundation
import IOKit
import IOKit.usb
import IOKit.usb.IOUSBLib

// MARK: - IOKit plug-in UUID definitions
// These constants exist as C macros in IOKit headers and aren't auto-imported into Swift;
// we recreate them here from the byte values in IOCFPlugIn.h / IOUSBLib.h.

private let kIOCFPlugInInterfaceID_swift = CFUUIDGetConstantUUIDWithBytes(
    nil,
    0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4,
    0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F
)

private let kIOUSBDeviceUserClientTypeID_swift = CFUUIDGetConstantUUIDWithBytes(
    nil,
    0x9d, 0xc7, 0xb7, 0x80, 0x9e, 0xc0, 0x11, 0xD4,
    0xa5, 0x4f, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61
)

// kIOUSBDeviceInterfaceID (the original; macOS 10.4+). Sufficient for DeviceRequest.
private let kIOUSBDeviceInterfaceID_swift = CFUUIDGetConstantUUIDWithBytes(
    nil,
    0x5c, 0x81, 0x87, 0xd0, 0x9e, 0xf3, 0x11, 0xD4,
    0x8b, 0x45, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61
)

// MARK: - UVC class-specific constants

private let UVC_SET_CUR: UInt8 = 0x01

private let CT_AE_MODE_CONTROL: UInt8 = 0x02
private let CT_EXPOSURE_TIME_ABSOLUTE_CONTROL: UInt8 = 0x04

// CT_AE_MODE_CONTROL value bitmap (per UVC 1.5 §4.2.2.1.2)
private let AE_MODE_MANUAL: UInt8 = 0x01            // bit 0 — manual exposure, manual iris
private let AE_MODE_AUTO: UInt8 = 0x02              // bit 1 — auto exposure, auto iris
private let AE_MODE_SHUTTER_PRIORITY: UInt8 = 0x04  // bit 2 — manual exposure, auto iris
private let AE_MODE_APERTURE_PRIORITY: UInt8 = 0x08 // bit 3 — auto exposure, manual iris

/// Sends UVC class-specific control requests to a USB camera via IOKit.
/// Used to apply manual shutter speed (exposure time) on UVC cameras like ELP-USB4KCAM30H-CFV
/// that don't expose `.custom` exposure mode through AVFoundation on macOS.
final class UVCExposureControl {

    // The outer double pointer that owns the IOUSBDeviceInterface.
    // Layout: deviceInterface (**) → inner (*) → struct of function pointers
    private var deviceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>?
    private var didOpen = false

    // Camera Terminal ID — webcams almost always use ID 1.
    // Could be discovered by parsing class-specific descriptors but this is the de-facto default.
    var cameraTerminalID: UInt8 = 1
    // Video Control interface number — typically 0 on UVC cameras.
    var interfaceNumber: UInt8 = 0

    init?(matchingProductName name: String) {
        guard let interface = UVCExposureControl.findAndOpen(productNameContains: name) else {
            return nil
        }
        self.deviceInterface = interface
        self.didOpen = true
    }

    deinit {
        if let outer = deviceInterface, let inner = outer.pointee {
            if didOpen {
                _ = inner.pointee.USBDeviceClose(outer)
            }
            _ = inner.pointee.Release(outer)
        }
    }

    // MARK: - Public API

    /// Switch to auto exposure.
    @discardableResult
    func setAutoExposure() -> Bool {
        return sendAEMode(AE_MODE_AUTO)
    }

    /// Apply a manual shutter speed (exposure time) in seconds.
    /// Uses "aperture priority" AE mode: manual exposure, auto iris (most cameras don't have iris).
    @discardableResult
    func setManualShutter(seconds: Double) -> Bool {
        // Aperture priority = manual shutter, auto iris (works on more cameras than pure manual)
        guard sendAEMode(AE_MODE_APERTURE_PRIORITY) || sendAEMode(AE_MODE_MANUAL) else {
            return false
        }
        // CT_EXPOSURE_TIME_ABSOLUTE_CONTROL units are 100 µs (UInt32, little-endian)
        let units = UInt32(max(1.0, (seconds * 10_000.0).rounded()))
        return sendExposureTimeAbsolute(units)
    }

    // MARK: - Internal helpers

    private func sendAEMode(_ mode: UInt8) -> Bool {
        var value = mode
        return withUnsafeMutablePointer(to: &value) { ptr in
            sendControlRequest(
                controlSelector: CT_AE_MODE_CONTROL,
                data: UnsafeMutableRawPointer(ptr),
                length: 1
            )
        }
    }

    private func sendExposureTimeAbsolute(_ units: UInt32) -> Bool {
        var value = units.littleEndian
        return withUnsafeMutablePointer(to: &value) { ptr in
            sendControlRequest(
                controlSelector: CT_EXPOSURE_TIME_ABSOLUTE_CONTROL,
                data: UnsafeMutableRawPointer(ptr),
                length: 4
            )
        }
    }

    private func sendControlRequest(controlSelector: UInt8, data: UnsafeMutableRawPointer, length: UInt16) -> Bool {
        guard let outer = deviceInterface, let inner = outer.pointee else {
            print("⚠️ UVC: no device interface")
            return false
        }

        var request = IOUSBDevRequest()
        // 0b00100001 = Host→Device, Class, Interface
        request.bmRequestType = 0x21
        request.bRequest = UVC_SET_CUR
        request.wValue = UInt16(controlSelector) << 8
        request.wIndex = (UInt16(cameraTerminalID) << 8) | UInt16(interfaceNumber)
        request.wLength = length
        request.pData = data

        // COM convention: `self` is the outer double pointer (the COM object identity),
        // not the inner struct pointer.
        let kr = inner.pointee.DeviceRequest(outer, &request)
        if kr != kIOReturnSuccess {
            print("⚠️ UVC DeviceRequest CS=\(controlSelector) failed: kr=0x\(String(format: "%08x", UInt32(bitPattern: kr)))")
            return false
        }
        return true
    }

    // MARK: - USB device discovery & open

    private static func findAndOpen(productNameContains needle: String) -> UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>? {
        guard let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) else {
            return nil
        }

        var iterator: io_iterator_t = 0
        let svcResult = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard svcResult == KERN_SUCCESS else {
            print("⚠️ UVC: IOServiceGetMatchingServices failed (\(svcResult))")
            return nil
        }
        defer { IOObjectRelease(iterator) }

        let needleLower = needle.lowercased().trimmingCharacters(in: .whitespaces)
        var deviceCount = 0
        var device = IOIteratorNext(iterator)
        while device != 0 {
            deviceCount += 1
            let productProperty = IORegistryEntryCreateCFProperty(
                device,
                "USB Product Name" as CFString,
                kCFAllocatorDefault,
                0
            )
            let productName = (productProperty?.takeRetainedValue() as? String) ?? ""
            let productLower = productName.lowercased().trimmingCharacters(in: .whitespaces)

            let matches = !productLower.isEmpty &&
                (productLower.contains(needleLower) || needleLower.contains(productLower))

            print("📷 UVC: scan device #\(deviceCount): name='\(productName)' matches=\(matches)")

            if matches {
                if let interface = openDeviceInterface(device) {
                    IOObjectRelease(device)
                    print("📷 UVC: opened USB device '\(productName)'")
                    return interface
                } else {
                    print("⚠️ UVC: failed to open matched device '\(productName)'")
                }
            }

            IOObjectRelease(device)
            device = IOIteratorNext(iterator)
        }
        print("⚠️ UVC: scanned \(deviceCount) USB device(s); none matched '\(needle)'")
        return nil
    }

    private static func openDeviceInterface(_ device: io_service_t) -> UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>? {
        var pluginInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0

        let pluginResult = IOCreatePlugInInterfaceForService(
            device,
            kIOUSBDeviceUserClientTypeID_swift,
            kIOCFPlugInInterfaceID_swift,
            &pluginInterface,
            &score
        )
        guard pluginResult == KERN_SUCCESS,
              let pluginOuter = pluginInterface,
              let pluginInner = pluginOuter.pointee else {
            print("⚠️ UVC: IOCreatePlugInInterfaceForService failed (\(pluginResult))")
            return nil
        }
        // COM convention: pass the OUTER double pointer as `self` to vtable methods.
        defer {
            _ = pluginInner.pointee.Release(pluginOuter)
        }

        // QueryInterface for IOUSBDeviceInterface
        var deviceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>?
        let queryResult: Int32 = withUnsafeMutablePointer(to: &deviceInterface) { ptr in
            ptr.withMemoryRebound(to: UnsafeMutableRawPointer?.self, capacity: 1) { lpvoidPtr in
                pluginInner.pointee.QueryInterface(
                    pluginOuter,
                    CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID_swift),
                    lpvoidPtr
                )
            }
        }

        guard queryResult == 0,
              let deviceOuter = deviceInterface,
              let deviceInner = deviceOuter.pointee else {
            print("⚠️ UVC: QueryInterface failed (\(queryResult))")
            return nil
        }

        // Open the device. DeviceRequest on endpoint 0 requires the device to be open.
        // This usually works alongside AVFoundation because AVF claims only the streaming
        // interface, not the device itself.
        let openResult = deviceInner.pointee.USBDeviceOpen(deviceOuter)
        if openResult != kIOReturnSuccess {
            print("⚠️ UVC: USBDeviceOpen failed (kr=0x\(String(format: "%08x", UInt32(bitPattern: openResult)))) — control requests will fail")
            _ = deviceInner.pointee.Release(deviceOuter)
            return nil
        }

        return deviceOuter
    }
}
