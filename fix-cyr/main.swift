// fix-cyr: instant layout toggle on a single key.
// --key fn (default): Globe pressed and released with no other key in between -> switch layout.
//                     Globe + any other key (F-keys, arrows, Globe+E...) -> ignored.
// --key f18:          switch on F18 key down (Caps Lock remapped to F18 by Karabiner or hidutil).
//                     F18 is swallowed, so no app sees it (needs Accessibility besides Input Monitoring).
// --layout-a / --layout-b: input source IDs to toggle between.
// --hidutil-capslock: remap Caps Lock -> F18 with hidutil at start (machines without Karabiner).

import Carbon
import CoreGraphics
import Foundation

func arg(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let layoutA = arg("--layout-a") ?? "com.apple.keylayout.ABC"
let layoutB = arg("--layout-b") ?? "com.apple.keylayout.Bulgarian-Phonetic"
let fnKeyCode: Int64 = 63  // kVK_Function
let f18KeyCode: Int64 = 79  // kVK_F18
let key = arg("--key") ?? "fn"
guard key == "fn" || key == "f18" else {
    FileHandle.standardError.write("fix-cyr: --key must be fn or f18\n".data(using: .utf8)!)
    exit(2)
}

var fnDown = false
var otherPressed = false
var tap: CFMachPort?

var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)

func inputSource(_ id: String) -> TISInputSource? {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return nil }
    return list.first
}

func currentID() -> String {
    let src = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

// eventTime: CGEvent timestamp of the key event that triggered the toggle
func toggle(eventTime: UInt64) {
    let target = currentID() == layoutA ? layoutB : layoutA
    guard let src = inputSource(target) else {
        log("toggle -> \(target) FAILED: input source not enabled")
        return
    }
    let t0 = mach_absolute_time()
    TISSelectInputSource(src)
    let t1 = mach_absolute_time()
    log("toggle -> \(target) select \(ms(ns(t1 - t0))) ms, key to done \(keyToDone(eventTime: eventTime)) ms")
}

func ns(_ ticks: UInt64) -> UInt64 { ticks * UInt64(timebase.numer) / UInt64(timebase.denom) }

func ms(_ nanos: UInt64) -> String { String(format: "%.2f", Double(nanos) / 1_000_000) }

// CGEventTimestamp is documented as nanoseconds since boot, but may be mach_absolute_time ticks
// (they differ on Apple Silicon). Only the matching clock gives a non-negative, small difference.
func keyToDone(eventTime: UInt64) -> String {
    let mach = mach_absolute_time()
    let uptimeNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    let candidates = [mach >= eventTime ? ns(mach - eventTime) : nil,
                      uptimeNs >= eventTime ? uptimeNs - eventTime : nil].compactMap { $0 }
    guard let d = candidates.min(), d < 10_000_000_000 else { return "?" }
    return ms(d)
}

func log(_ msg: String) {
    FileHandle.standardError.write("\(Date()) \(msg)\n".data(using: .utf8)!)
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    case .keyDown where key == "f18", .keyUp where key == "f18":
        guard event.getIntegerValueField(.keyboardEventKeycode) == f18KeyCode else { break }
        if type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            toggle(eventTime: event.timestamp)
        }
        return nil  // swallow F18: a terminal sends it as ESC[32~ and zsh inserts "~"
    case .flagsChanged where key == "fn":
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        log("flagsChanged code=\(code) flags=\(event.flags.rawValue)")
        if code == fnKeyCode {
            let down = event.flags.contains(.maskSecondaryFn)
            log("fn \(down ? "down" : "up") other=\(otherPressed)")
            if down && !fnDown {
                fnDown = true
                otherPressed = false
            } else if !down && fnDown {
                fnDown = false
                if !otherPressed { toggle(eventTime: event.timestamp) }
            }
        } else if fnDown {
            otherPressed = true  // another modifier together with Globe
        }
    case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown:
        if fnDown { otherPressed = true }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

if CommandLine.arguments.contains("--hidutil-capslock") {
    // HID usage 0x39 Caps Lock -> 0x6D F18; does not survive reboot, so it is applied on every start
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
    p.arguments = ["property", "--set",
                   #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}"#]
    p.standardOutput = FileHandle.nullDevice
    do {
        try p.run()
        p.waitUntilExit()
        log("hidutil Caps Lock -> F18 status=\(p.terminationStatus)")
    } catch {
        log("hidutil Caps Lock -> F18 FAILED: \(error)")
    }
}

// F18 mode filters events (to swallow F18), which needs Accessibility; Globe mode only listens
let filtering = key == "f18"
let mask: CGEventMask = [CGEventType.flagsChanged, .keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown]
    .reduce(0) { $0 | (1 << $1.rawValue) }

if !CGPreflightListenEventAccess() { CGRequestListenEventAccess() }  // adds fix-cyr to Input Monitoring list
if filtering && !CGPreflightPostEventAccess() { CGRequestPostEventAccess() }  // adds fix-cyr to Accessibility list
func accessGranted() -> Bool { CGPreflightListenEventAccess() && (!filtering || CGPreflightPostEventAccess()) }

guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                options: filtering ? .defaultTap : .listenOnly,
                                eventsOfInterest: mask, callback: callback, userInfo: nil) else {
    let needed = filtering ? "Input Monitoring and Accessibility" : "Input Monitoring"
    FileHandle.standardError.write("fix-cyr: no event tap - grant \(needed) in Privacy & Security\n".data(using: .utf8)!)
    sleep(5)
    exit(1)  // launchd restarts us until access is granted
}
tap = t
log("started key=\(key) layouts=\(layoutA),\(layoutB) listen access=\(CGPreflightListenEventAccess())"
    + (filtering ? " accessibility=\(CGPreflightPostEventAccess())" : ""))
if !accessGranted() { sleep(5); exit(1) }  // launchd restarts us until access is granted
CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
CGEvent.tapEnable(tap: t, enable: true)
CFRunLoopRun()
