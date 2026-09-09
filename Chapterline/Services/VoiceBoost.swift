import AVFoundation
import AudioToolbox
import Foundation

/// Gain + peak clip applied through an audio mix tap. AVPlayer.volume cannot exceed 1.0.
final class BoostState: @unchecked Sendable {
    var gain: Float = 1
}

enum VoiceBoost {
    static func attach(to item: AVPlayerItem, state: BoostState) async {
        guard let tracks = try? await item.asset.loadTracks(withMediaType: .audio), let track = tracks.first else { return }
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(state).toOpaque(),
            init: { _, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { tap in
                let storage = MTAudioProcessingTapGetStorage(tap)
                Unmanaged<BoostState>.fromOpaque(storage).release()
            },
            prepare: { _, _, _ in },
            unprepare: { _ in },
            process: { tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut in
                var localFlags = flags
                MTAudioProcessingTapGetSourceAudio(
                    tap,
                    numberFrames,
                    bufferListInOut,
                    &localFlags,
                    nil,
                    numberFramesOut
                )
                flagsOut.pointee = localFlags
                let storage = MTAudioProcessingTapGetStorage(tap)
                let boost = Unmanaged<BoostState>.fromOpaque(storage).takeUnretainedValue()
                let gain = boost.gain
                guard gain > 1.001 else { return }
                let buffers = UnsafeMutableAudioBufferListPointer(bufferListInOut)
                for buffer in buffers {
                    guard let pointer = buffer.mData else { continue }
                    let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    let samples = pointer.bindMemory(to: Float.self, capacity: sampleCount)
                    for i in 0..<sampleCount {
                        let boosted = samples[i] * gain
                        samples[i] = max(-0.95, min(0.95, boosted))
                    }
                }
            }
        )

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tap
        )
        guard status == noErr, let tap else { return }

        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        item.audioMix = mix
    }
}
