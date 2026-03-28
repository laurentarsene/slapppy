//
//  AccelerometerReader.swift
//  Slappy
//
//  Created by Arsène Laurent on 28/03/2026.
//

import IOKit
import IOKit.hid
import Foundation

// Bosch BMI286 IMU report constants (AppleSPUHIDDevice, Apple Silicon)
private let kIMUReportLen  = 22    // Expected report length in bytes
private let kIMUDataOffset = 6     // XYZ payload start (3× int32 LE)
private let kIMUDecimation = 8     // Keep 1 in N samples for UI refresh
private let kReportBufSize = 4096

// Slap detection — envelope-tracking approach
// The background (fan/coil) creates a sustained oscillation of ~100-130 units above the EMA.
// We track the upper envelope of that noise and only fire when the deviation is
// kSlapMargin units above it. Updating the envelope is gated so slap peaks don't
// inflate the threshold and block subsequent slaps in a pattern.
private let kNoiseGate:           Double = 150.0  // deviations above this are treated as slap, not noise
private let kNoiseEnvelopeDecay:  Double = 0.999  // per 1 kHz sample (~700 ms half-life)
private let kSlapMargin:          Double = 100.0  // threshold = noiseEnvelope + kSlapMargin
private let kSlapRefractory:      Double = 0.3    // min seconds between slaps
private let kEMAAlpha:            Double = 0.001  // gravity EMA (~1 s time constant at 1 kHz)
private let kEMAWarmupAlpha:      Double = 0.01   // fast warmup alpha (~100-sample convergence)
private let kEMAWarmup:           Int    = 500    // samples before detection starts (~0.5 s)

@Observable
final class AccelerometerReader {
    var x: Double = 0
    var y: Double = 0
    var z: Double = 0
    var magnitude: Double = 0
    var isAvailable = false
    var peakMagnitude: Double = 0
    var slapCount: Int = 0
    var lastSlapDate: Date = .distantPast  // timestamp of most recent detected slap

    /// Called on the main thread immediately when a slap is detected.
    /// The parameter is the raw deviation above the EMA baseline (the slap's intensity).
    /// Set this to hook into pattern recording / matching without requiring the UI to be open.
    var onSlap: ((Double) -> Void)?

    // Internal slap-detection state (MainActor, not observed by UI)
    @ObservationIgnored private var slowEMA: Double = 0
    @ObservationIgnored private var noiseEnvelope: Double = 0
    @ObservationIgnored private var warmupSamples: Int = 0
    @ObservationIgnored private var lastSlapTime: CFAbsoluteTime = 0
    @ObservationIgnored private var uiDecimation: Int = 0

    nonisolated(unsafe) private var hidDevice: IOHIDDevice?
    nonisolated(unsafe) private var reportBuffer: UnsafeMutablePointer<UInt8>?

    func start() {
        guard hidDevice == nil else { return }  // already running
        wakeDrivers()
        if registerDevice() {
            isAvailable = true
        }
    }

    private func wakeDrivers() {
        let matching = IOServiceMatching("AppleSPUHIDDriver")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var svc = IOIteratorNext(iterator)
        while svc != 0 {
            IORegistryEntrySetCFProperty(svc, "SensorPropertyReportingState" as CFString, NSNumber(value: 1))
            IORegistryEntrySetCFProperty(svc, "SensorPropertyPowerState"     as CFString, NSNumber(value: 1))
            IORegistryEntrySetCFProperty(svc, "ReportInterval"               as CFString, NSNumber(value: 1000))
            IOObjectRelease(svc)
            svc = IOIteratorNext(iterator)
        }
        print("[Slapppy] Drivers woken")
    }

    private func registerDevice() -> Bool {
        let matching = IOServiceMatching("AppleSPUHIDDevice")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }

        var svc = IOIteratorNext(iterator)
        while svc != 0 {
            let usagePage = ioRegistryInt(svc, key: "PrimaryUsagePage")
            let usage     = ioRegistryInt(svc, key: "PrimaryUsage")
            print("[Slapppy] AppleSPUHIDDevice page=0x\(String(usagePage, radix: 16)) usage=\(usage)")

            if usagePage == 0xFF00 && usage == 3 {
                guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, svc) else {
                    IOObjectRelease(svc); svc = IOIteratorNext(iterator); continue
                }
                guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
                    print("[Slapppy] IOHIDDeviceOpen failed")
                    IOObjectRelease(svc); svc = IOIteratorNext(iterator); continue
                }

                let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: kReportBufSize)
                buf.initialize(repeating: 0, count: kReportBufSize)
                reportBuffer = buf
                hidDevice = device

                let ctx = Unmanaged.passUnretained(self).toOpaque()
                IOHIDDeviceRegisterInputReportCallback(
                    device, buf, CFIndex(kReportBufSize),
                    { ctx, _, _, _, _, report, length in
                        guard let ctx, length == kIMUReportLen else { return }
                        let r = Unmanaged<AccelerometerReader>.fromOpaque(ctx).takeUnretainedValue()

                        let off = kIMUDataOffset
                        let rawX = Int32(bitPattern: UInt32(report[off])   | UInt32(report[off+1]) << 8 | UInt32(report[off+2])  << 16 | UInt32(report[off+3])  << 24)
                        let rawY = Int32(bitPattern: UInt32(report[off+4]) | UInt32(report[off+5]) << 8 | UInt32(report[off+6])  << 16 | UInt32(report[off+7])  << 24)
                        let rawZ = Int32(bitPattern: UInt32(report[off+8]) | UInt32(report[off+9]) << 8 | UInt32(report[off+10]) << 16 | UInt32(report[off+11]) << 24)
                        let mag = (Double(rawX)*Double(rawX) + Double(rawY)*Double(rawY) + Double(rawZ)*Double(rawZ)).squareRoot()

                        MainActor.assumeIsolated {
                            r.warmupSamples += 1

                            if r.warmupSamples <= kEMAWarmup {
                                // Warmup: fast-converge EMA and build initial noise envelope.
                                // Gate applied here too so a slap during warmup doesn't inflate
                                // the envelope and break detection after warmup ends.
                                if r.slowEMA == 0 { r.slowEMA = mag }
                                r.slowEMA = r.slowEMA * (1 - kEMAWarmupAlpha) + mag * kEMAWarmupAlpha
                                let posdev = max(0, mag - r.slowEMA)
                                if posdev < kNoiseGate {
                                    r.noiseEnvelope = max(r.noiseEnvelope * kNoiseEnvelopeDecay, posdev)
                                }
                            } else {
                                // Detection phase
                                r.slowEMA = r.slowEMA * (1 - kEMAAlpha) + mag * kEMAAlpha
                                let posdev = max(0, mag - r.slowEMA)

                                // Only update envelope from background samples (not from slaps)
                                if posdev < kNoiseGate {
                                    r.noiseEnvelope = max(r.noiseEnvelope * kNoiseEnvelopeDecay, posdev)
                                }

                                let threshold = r.noiseEnvelope + kSlapMargin
                                if posdev > threshold {
                                    let now = CFAbsoluteTimeGetCurrent()
                                    if now - r.lastSlapTime > kSlapRefractory {
                                        r.lastSlapTime = now
                                        r.slapCount += 1
                                        r.lastSlapDate = Date()
                                        r.onSlap?(posdev)
                                        print("[Slapppy] Slap! #\(r.slapCount) dev=\(Int(posdev)) env=\(Int(r.noiseEnvelope)) threshold=\(Int(threshold))")
                                    }
                                }
                            }

                            // UI refresh at ~125 Hz (every 8 samples)
                            r.uiDecimation += 1
                            guard r.uiDecimation >= kIMUDecimation else { return }
                            r.uiDecimation = 0

                            r.x = Double(rawX)
                            r.y = Double(rawY)
                            r.z = Double(rawZ)
                            r.magnitude = mag
                            if mag > r.peakMagnitude { r.peakMagnitude = mag }
                        }
                    },
                    ctx
                )
                IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
                print("[Slapppy] Accelerometer registered")
                IOObjectRelease(svc)
                return true
            }

            IOObjectRelease(svc)
            svc = IOIteratorNext(iterator)
        }
        return false
    }

    private func ioRegistryInt(_ entry: io_registry_entry_t, key: String) -> Int64 {
        guard let ref = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0) else { return 0 }
        return (ref.takeRetainedValue() as? NSNumber)?.int64Value ?? 0
    }

    func stop() {
        if let buf = reportBuffer { buf.deallocate(); reportBuffer = nil }
        if let device = hidDevice {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            hidDevice = nil
        }
        isAvailable = false
    }
}
