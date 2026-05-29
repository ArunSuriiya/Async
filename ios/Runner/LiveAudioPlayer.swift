import Foundation
import AVFoundation
import AudioToolbox

class LiveAudioPlayer {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var speedNode: AVAudioUnitVarispeed?

    private var audioConverter: AudioConverterRef?
    private var isPlaying = false
    private var targetFormat: AVAudioFormat?

    fileprivate var currentOpusData: Data?
    fileprivate var tempBuffer = Data(count: 4096)

    init() {
        setupAudioEngine()
    }

    private func setupAudioEngine() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let speed = AVAudioUnitVarispeed()

        engine.attach(player)
        engine.attach(speed)

        // Mono 48000Hz 16-bit PCM format
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 1, interleaved: false)!
        self.targetFormat = format

        engine.connect(player, to: speed, format: format)
        engine.connect(speed, to: engine.mainMixerNode, format: format)

        self.audioEngine = engine
        self.playerNode = player
        self.speedNode = speed
    }

    func start(sampleRate: Double, channels: UInt32) {
        if isPlaying { stop() }

        // Configure input (Opus) and output (Linear PCM) basic descriptions
        var sourceFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatOpus,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 960,
            mBytesPerFrame: 0,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 0,
            mReserved: 0
        )

        var targetFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2 * channels,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2 * channels,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        let status = AudioConverterNew(&sourceFormat, &targetFormat, &audioConverter)
        if status != noErr {
            print("[iOS Player] Failed to create AudioConverter: \(status)")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)

            try audioEngine?.start()
            playerNode?.play()
            isPlaying = true
            print("[iOS Player] AVAudioEngine and AudioConverter initialized successfully")
        } catch {
            print("[iOS Player] Failed to start Audio Session or Engine: \(error.localizedDescription)")
        }
    }

    func stop() {
        isPlaying = false
        playerNode?.stop()
        audioEngine?.stop()
        if let converter = audioConverter {
            AudioConverterDispose(converter)
            audioConverter = nil
        }
        currentOpusData = nil
    }

    func playPacket(opusPacket: Data) {
        guard isPlaying, let converter = audioConverter else { return }

        self.currentOpusData = opusPacket

        let pcmBufferSize = 960 * 2 // 960 samples, 2 bytes each
        var outputData = Data(count: pcmBufferSize)

        var outputBufferList = AudioBufferList()
        outputBufferList.mNumberBuffers = 1

        outputData.withUnsafeMutableBytes { rawBufferPointer in
            outputBufferList.mBuffers.mNumberChannels = 1
            outputBufferList.mBuffers.mDataByteSize = UInt32(pcmBufferSize)
            outputBufferList.mBuffers.mData = rawBufferPointer.baseAddress
        }

        var ioOutputDataPackets: UInt32 = 960
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        let status = AudioConverterFillComplexBuffer(
            converter,
            inputDataProc,
            selfPointer,
            &ioOutputDataPackets,
            &outputBufferList,
            nil
        )

        if status == noErr && ioOutputDataPackets > 0 {
            schedulePCMBuffer(pcmData: outputData)
        } else if status != -1 {
            // Log other conversion status errors (-1 is just buffer exhausted, which is expected since we feed packet-by-packet)
            print("[iOS Player] AudioConverter conversion error: \(status)")
        }
    }

    private func schedulePCMBuffer(pcmData: Data) {
        guard let player = playerNode, let format = targetFormat else { return }

        let frameCount = AVAudioFrameCount(pcmData.count / 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        pcmData.withUnsafeBytes { rawBufferPointer in
            if let src = rawBufferPointer.baseAddress, let dst = buffer.int16ChannelData?[0] {
                memcpy(dst, src, pcmData.count)
            }
        }

        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    func setPlaybackSpeed(speed: Float) {
        speedNode?.rate = speed
    }

    func setVolume(volume: Float) {
        playerNode?.volume = volume
    }
}

// Complex Input Data Proc callback to supply data to CoreAudio converter
private let inputDataProc: AudioConverterComplexInputDataProc = { (
    inAudioConverter,
    ioNumberDataPackets,
    ioData,
    outDataPacketDescription,
    inUserData
) -> OSStatus in
    let player = Unmanaged<LiveAudioPlayer>.fromOpaque(inUserData!).takeUnretainedValue()

    guard let opusData = player.currentOpusData, !opusData.isEmpty else {
        ioNumberDataPackets.pointee = 0
        return -1 // Signal no data
    }

    let packetSize = opusData.count
    let buffer = UnsafeMutableAudioBufferListPointer(ioData)

    // Ensure tempBuffer capacity is sufficient
    if player.tempBuffer.count < packetSize {
        player.tempBuffer = Data(count: packetSize)
    }

    player.tempBuffer.replaceSubrange(0..<packetSize, with: opusData)

    buffer[0].mDataByteSize = UInt32(packetSize)
    buffer[0].mData = player.tempBuffer.withUnsafeMutableBytes { $0.baseAddress }
    buffer[0].mNumberChannels = 1

    if let outDescriptions = outDataPacketDescription {
        outDescriptions.pointee.mStartOffset = 0
        outDescriptions.pointee.mVariableFramesInPacket = 960
        outDescriptions.pointee.mDataByteSize = UInt32(packetSize)
    }

    ioNumberDataPackets.pointee = 1
    player.currentOpusData = nil // consume data
    return noErr
}
