import AudioToolbox
import CoreAudio
import Foundation
import Observation

/// Listens to what the Mac is playing and splits it into five bands, from the
/// bass to the treble, so the notch's bars can follow the music.
///
/// It uses a **Core Audio process tap** (macOS 14.2 and later): a copy of the
/// system's output, taken before it reaches the speakers, that only this app can
/// read. Nothing is recorded or stored, and nothing is sent anywhere; each block
/// of sound is reduced to five numbers and thrown away. The first time it starts,
/// macOS asks for the *System Audio Recording* permission.
///
/// It is **off unless the user turns it on**, it only runs while music plays, and
/// if anything about it fails the notch falls back to its simulated animation.
@MainActor
@Observable
final class AudioReactor {

    static let shared = AudioReactor()

    /// Five bands from bass to treble, each from 0 to 1.
    private(set) var levels: [Float] = Array(repeating: 0.2, count: 5)
    private(set) var isRunning = false
    /// Why it could not start, when it could not.
    private(set) var failure: String?

    @ObservationIgnored private var tapID = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var procID: AudioDeviceIOProcID?
    @ObservationIgnored private var analyser: BandAnalyser?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let queue = DispatchQueue(label: "com.mycss.audio-tap", qos: .userInteractive)

    // MARK: - Start and stop

    func start() {
        guard !isRunning else { return }
        failure = nil

        // 1. The tap: the whole system's output, with no process left out.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "MycSs visualiser"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &tap)
        guard tapStatus == noErr else {
            fail("the audio tap could not be created (\(tapStatus))")
            return
        }
        tapID = tap

        // 2. A private device that carries the tap, so it can be read.
        guard let output = Self.defaultOutputUID() else {
            fail("no output device")
            stop()
            return
        }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MycSs visualiser",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: output,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        let deviceStatus = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        guard deviceStatus == noErr else {
            fail("the audio device could not be created (\(deviceStatus))")
            stop()
            return
        }
        aggregateID = device

        // 3. What the tap delivers: sample rate and channel layout.
        let format = Self.tapFormat(tap)
        let analyser = BandAnalyser(sampleRate: Float(format?.mSampleRate ?? 48_000))
        self.analyser = analyser
        let interleavedChannels = Int(format?.mChannelsPerFrame ?? 2)
        let isNonInterleaved = (format?.mFormatFlags ?? 0) & kAudioFormatFlagIsNonInterleaved != 0

        // 4. Every block of sound goes to the analyser.
        var proc: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcIDWithBlock(&proc, device, queue) {
            _, input, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            analyser.process(buffers, channels: interleavedChannels, nonInterleaved: isNonInterleaved)
        }
        guard procStatus == noErr, let proc else {
            fail("the audio reader could not be created (\(procStatus))")
            stop()
            return
        }
        procID = proc

        let startStatus = AudioDeviceStart(device, proc)
        guard startStatus == noErr else {
            fail("the audio could not be started (\(startStatus))")
            stop()
            return
        }

        // The bars are refreshed thirty times a second.
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let analyser = self.analyser else { return }
                self.levels = analyser.snapshot()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        isRunning = true
        Log.line("audio: the visualiser is listening (\(Int(format?.mSampleRate ?? 0)) Hz, \(interleavedChannels) channels)")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        analyser = nil
        if isRunning { Log.line("audio: the visualiser stopped listening") }
        isRunning = false
        levels = Array(repeating: 0.2, count: 5)
    }

    private func fail(_ message: String) {
        failure = message
        Log.warn("audio: \(message)")
    }

    // MARK: - Core Audio helpers

    private static func defaultOutputUID() -> String? {
        guard let device = SystemAudio.defaultOutput() else { return nil }
        var property = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &property, 0, nil, &size, &uid)
        return status == noErr ? uid?.takeRetainedValue() as String? : nil
    }

    private static func tapFormat(_ tap: AudioObjectID) -> AudioStreamBasicDescription? {
        var property = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tap, &property, 0, nil, &size, &format)
        return status == noErr ? format : nil
    }
}

// MARK: - The analysis

/// Splits the sound into five bands with cheap one-pole filters, and keeps a
/// smoothed level for each.
///
/// No Fourier transform: for five bars that only have to feel like the music,
/// filters split at 150, 500, 1500 and 4000 Hz are enough, and they cost almost
/// nothing on the audio thread. Each band is divided by its own recent peak, so
/// quiet and loud songs move the bars alike.
final class BandAnalyser: @unchecked Sendable {

    private let lock = NSLock()
    private let alphas: [Float]
    private var filters = [Float](repeating: 0, count: 4)
    private var smoothed = [Float](repeating: 0, count: 5)
    private var peaks = [Float](repeating: 0.01, count: 5)

    init(sampleRate: Float) {
        let cutoffs: [Float] = [150, 500, 1500, 4000]
        alphas = cutoffs.map { 1 - exp(-2 * .pi * $0 / max(sampleRate, 8_000)) }
    }

    /// Called on the audio thread with each block of sound.
    func process(_ buffers: UnsafeMutableAudioBufferListPointer, channels: Int, nonInterleaved: Bool) {
        guard buffers.count > 0 else { return }

        // One mono signal: the first channel, or the average of the pair.
        let frames: Int
        let sample: (Int) -> Float
        if nonInterleaved {
            guard let left = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
            frames = Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size
            if buffers.count > 1, let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) {
                sample = { (left[$0] + right[$0]) * 0.5 }
            } else {
                sample = { left[$0] }
            }
        } else {
            guard let data = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
            let step = max(channels, 1)
            frames = Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size / step
            sample = step > 1 ? { (data[$0 * step] + data[$0 * step + 1]) * 0.5 } : { data[$0] }
        }
        guard frames > 0 else { return }

        lock.lock()
        defer { lock.unlock() }

        var sums = [Float](repeating: 0, count: 5)
        for index in 0..<frames {
            let x = sample(index)
            filters[0] += alphas[0] * (x - filters[0])
            filters[1] += alphas[1] * (x - filters[1])
            filters[2] += alphas[2] * (x - filters[2])
            filters[3] += alphas[3] * (x - filters[3])
            let b0 = filters[0]
            let b1 = filters[1] - filters[0]
            let b2 = filters[2] - filters[1]
            let b3 = filters[3] - filters[2]
            let b4 = x - filters[3]
            sums[0] += b0 * b0
            sums[1] += b1 * b1
            sums[2] += b2 * b2
            sums[3] += b3 * b3
            sums[4] += b4 * b4
        }

        for band in 0..<5 {
            let rms = (sums[band] / Float(frames)).squareRoot()
            // The peak falls slowly, so a loud moment does not flatten what follows.
            peaks[band] = max(rms, peaks[band] * 0.9985, 0.004)
            let target = min(powf(rms / peaks[band], 1.3), 1)
            // Up fast, down slowly.
            smoothed[band] = target > smoothed[band]
                ? smoothed[band] * 0.35 + target * 0.65
                : smoothed[band] * 0.88 + target * 0.12
        }
    }

    func snapshot() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return smoothed
    }
}
