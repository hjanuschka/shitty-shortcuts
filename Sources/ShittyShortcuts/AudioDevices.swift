import CoreAudio
import Foundation

// Enumerate audio input devices via CoreAudio.
enum AudioDevices {
    static func inputDeviceNames() -> [String] {
        var names: [String] = []

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &dataSize) == noErr else { return names }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIds = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &dataSize, &deviceIds) == noErr else { return names }

        for deviceId in deviceIds {
            // Does it have input channels?
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceId, &streamAddress, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { continue }

            let bufferList = UnsafeMutableRawPointer.allocate(byteCount: Int(streamSize),
                                                              alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { bufferList.deallocate() }
            guard AudioObjectGetPropertyData(deviceId, &streamAddress, 0, nil, &streamSize, bufferList) == noErr else { continue }
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList.assumingMemoryBound(to: AudioBufferList.self))
            let channels = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard channels > 0 else { continue }

            // Device name.
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(deviceId, &nameAddress, 0, nil, &nameSize, &name) == noErr,
               let name {
                names.append(name.takeRetainedValue() as String)
            }
        }
        return names
    }
}
