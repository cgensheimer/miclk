import CoreGraphics
import Foundation

final class EventTapManager {

    var onCapsLockChanged: ((_ capsLockOn: Bool, _ shiftHeld: Bool) -> Void)?

    fileprivate var lastCapsLockState: Bool = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    @discardableResult
    func start() -> Bool {
        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: userInfo
        ) else {
            return false
        }

        eventTap = tap

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }

        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }

    fileprivate func reEnableTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    deinit {
        stop()
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<EventTapManager>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout {
        manager.reEnableTap()
        return Unmanaged.passUnretained(event)
    }

    guard type == .flagsChanged else {
        return Unmanaged.passUnretained(event)
    }

    let capsLockOn = event.flags.contains(.maskAlphaShift)

    if capsLockOn != manager.lastCapsLockState {
        manager.lastCapsLockState = capsLockOn
        let shiftHeld = event.flags.contains(.maskShift)
        manager.onCapsLockChanged?(capsLockOn, shiftHeld)
        return nil
    }

    return Unmanaged.passUnretained(event)
}
