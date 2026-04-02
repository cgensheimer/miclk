import CoreAudio
import Foundation

final class AudioManager {

    var onMuteChanged: ((Bool) -> Void)?
    var onDefaultDeviceChanged: (() -> Void)?

    private var muteListenerDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?

    func isMuted() -> Bool {
        let deviceID = defaultInputDevice()
        guard deviceID != kAudioObjectUnknown else { return false }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var mute: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &mute)
        guard status == noErr else { return false }

        return mute != 0
    }

    func setMute(_ muted: Bool) {
        let deviceID = defaultInputDevice()
        guard deviceID != kAudioObjectUnknown else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            print("miclk: default input device does not support mute")
            return
        }

        var mute: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &mute)
        if status != noErr {
            print("miclk: failed to set mute state, OSStatus \(status)")
        }
    }

    func defaultInputDevice() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr else { return kAudioObjectUnknown }
        return deviceID
    }

    func startListening() {
        installDefaultDeviceListener()
        installMuteListener(for: defaultInputDevice())
    }

    func stopListening() {
        removeDefaultDeviceListener()
        removeMuteListener()
    }

    private func installDefaultDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.removeMuteListener()
            let newDevice = self.defaultInputDevice()
            self.installMuteListener(for: newDevice)
            self.onDefaultDeviceChanged?()
        }

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )

        if status == noErr {
            defaultDeviceListenerBlock = block
        }
    }

    private func removeDefaultDeviceListener() {
        guard let block = defaultDeviceListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block
        )
        defaultDeviceListenerBlock = nil
    }

    private func installMuteListener(for deviceID: AudioDeviceID) {
        guard deviceID != kAudioObjectUnknown else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            let muted = self.isMuted()
            self.onMuteChanged?(muted)
        }

        let status = AudioObjectAddPropertyListenerBlock(
            deviceID, &address, DispatchQueue.main, block
        )

        if status == noErr {
            muteListenerDeviceID = deviceID
            muteListenerBlock = block
        }
    }

    private func removeMuteListener() {
        guard muteListenerDeviceID != kAudioObjectUnknown, let block = muteListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            muteListenerDeviceID, &address, DispatchQueue.main, block
        )
        muteListenerDeviceID = kAudioObjectUnknown
        muteListenerBlock = nil
    }
}
