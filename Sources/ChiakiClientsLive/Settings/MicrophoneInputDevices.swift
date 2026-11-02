import AVFoundation
import AudioToolbox
import Foundation
#if os(macOS)
    import CoreAudio
#endif

/// Lists the audio inputs the microphone can capture from and points an audio engine's input node at a chosen
/// one, using Core Audio on macOS and the audio session on iOS.
public enum MicrophoneInputDevices {
    #if os(macOS)
        /// A Core Audio device identifier on macOS.
        public typealias DeviceID = AudioDeviceID
    #else
        /// An audio session port UID on iOS.
        public typealias DeviceID = String
    #endif

    /// An audio input that can be selected for microphone capture.
    struct Device: Equatable {
        /// The platform identifier used to select the input.
        let id: DeviceID
        /// The name shown to the user and stored in sound settings.
        let name: String
    }

    /// Returns the names of every available input, without duplicates, in system order.
    public static func names() -> [String] {
        var seen = Set<String>()
        return devices().map(\.name).filter {
            seen.insert($0).inserted
        }
    }

    /// Looks up an available input by its display name.
    /// - Parameter name: The name stored in sound settings.
    /// - Returns: The input's identifier, or `nil` when no connected input has that name.
    public static func device(named name: String) -> DeviceID? {
        devices().first {
            $0.name == name
        }?.id
    }

    #if os(macOS)
        /// Makes the input node capture from the given Core Audio device.
        /// - Parameters:
        ///   - device: The device to capture from.
        ///   - input: The engine's input node.
        public static func assign(_ device: DeviceID, on input: AVAudioInputNode) {
            guard let unit = input.audioUnit else {
                return
            }
            var value = device
            _ = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &value,
                UInt32(MemoryLayout<DeviceID>.size)
            )
        }

        /// Returns the Core Audio device the input node currently captures from.
        /// - Parameter input: The engine's input node.
        /// - Returns: The device identifier, or `nil` when it cannot be read.
        public static func current(_ input: AVAudioInputNode) -> DeviceID? {
            guard let unit = input.audioUnit else {
                return nil
            }
            var value = DeviceID(0)
            var size = UInt32(MemoryLayout<DeviceID>.size)
            let status = AudioUnitGetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &value,
                &size
            )
            guard status == noErr else {
                return nil
            }
            return value
        }

        /// Returns every Core Audio device that has at least one input channel and a name.
        static func devices() -> [Device] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
            ) == noErr, size > 0 else {
                return []
            }
            var identifiers = [DeviceID](
                repeating: 0,
                count: Int(size) / MemoryLayout<DeviceID>.size
            )
            guard AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &identifiers
            ) == noErr else {
                return []
            }
            return identifiers.compactMap { identifier in
                guard hasInput(identifier), let name = name(identifier) else {
                    return nil
                }
                return Device(id: identifier, name: name)
            }
        }

        private static func hasInput(_ device: DeviceID) -> Bool {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
                return false
            }
            let storage = UnsafeMutableRawPointer.allocate(
                byteCount: Int(size),
                alignment: MemoryLayout<AudioBufferList>.alignment
            )
            defer {
                storage.deallocate()
            }
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr else {
                return false
            }
            let buffers = UnsafeMutableAudioBufferListPointer(storage
                .assumingMemoryBound(to: AudioBufferList.self))
            return buffers.contains {
                $0.mNumberChannels > 0
            }
        }

        private static func name(_ device: DeviceID) -> String? {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var value: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
                  let name = value?.takeRetainedValue() as String?,
                  !name.isEmpty else {
                return nil
            }
            return name
        }
    #else
        /// Sets the audio session's preferred input to the port with the given UID.
        /// - Parameters:
        ///   - device: The UID of the port to prefer.
        ///   - input: The engine's input node, unused on iOS.
        public static func assign(_ device: DeviceID, on input: AVAudioInputNode) {
            let session = AVAudioSession.sharedInstance()
            let port = session.availableInputs?.first {
                $0.uid == device
            }
            try? session.setPreferredInput(port)
        }

        /// Returns the UID of the first input in the audio session's current route.
        /// - Parameter input: The engine's input node, unused on iOS.
        /// - Returns: The port UID, or `nil` when the route has no input.
        public static func current(_ input: AVAudioInputNode) -> DeviceID? {
            AVAudioSession.sharedInstance().currentRoute.inputs.first?.uid
        }

        /// Returns every input port the audio session currently offers.
        static func devices() -> [Device] {
            (AVAudioSession.sharedInstance().availableInputs ?? []).map {
                Device(id: $0.uid, name: $0.portName)
            }
        }
    #endif
}
