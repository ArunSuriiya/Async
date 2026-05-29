package com.async.async_share

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.PlaybackParams
import android.os.Build
import android.util.Log
import io.github.jaredmdobson.concentus.OpusDecoder

class LiveAudioPlayer {
    companion object {
        private const val TAG = "LiveAudioPlayer"
    }

    private var audioTrack: AudioTrack? = null
    private var decoder: OpusDecoder? = null
    private var isPlaying = false
    private var sampleRate = 48000
    private var channels = 1

    fun start(sampleRate: Int, channels: Int) {
        if (isPlaying) stop()

        this.sampleRate = sampleRate
        this.channels = channels

        val channelConfig = if (channels == 2) AudioFormat.CHANNEL_OUT_STEREO else AudioFormat.CHANNEL_OUT_MONO
        val encoding = AudioFormat.ENCODING_PCM_16BIT
        val minBufferSize = AudioTrack.getMinBufferSize(sampleRate, channelConfig, encoding)
        // Ensure buffer can hold 30ms of audio for ultra-low-latency playback
        val bufferSize = Math.max(minBufferSize, (sampleRate * channels * 2 * 0.030).toInt())

        try {
            decoder = OpusDecoder(sampleRate, channels)

            audioTrack = AudioTrack.Builder()
                .setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build())
                .setAudioFormat(AudioFormat.Builder()
                    .setEncoding(encoding)
                    .setSampleRate(sampleRate)
                    .setChannelMask(channelConfig)
                    .build())
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()

            audioTrack?.play()
            isPlaying = true
            Log.i(TAG, "AudioTrack player started successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start AudioTrack: ${e.message}", e)
        }
    }

    fun stop() {
        isPlaying = false
        try {
            audioTrack?.stop()
            audioTrack?.flush()
            audioTrack?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping AudioTrack: ${e.message}")
        }
        audioTrack = null
        decoder = null
    }

    fun playPacket(opusData: ByteArray) {
        if (!isPlaying || audioTrack == null || decoder == null) return

        // 20ms at 48kHz mono = 960 samples
        val frameSize = 960
        val pcmOut = ShortArray(frameSize * channels)

        try {
            val decoderRef = decoder
            if (decoderRef != null) {
                val decodedSamples = decoderRef.decode(opusData, 0, opusData.size, pcmOut, 0, frameSize, false)
                if (decodedSamples > 0) {
                    audioTrack?.write(pcmOut, 0, decodedSamples * channels)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Opus decode error: ${e.message}")
        }
    }

    fun setPlaybackSpeed(speed: Float) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                audioTrack?.let { track ->
                    if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                        val params = track.playbackParams ?: PlaybackParams()
                        params.speed = speed
                        track.playbackParams = params
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error adjusting playback speed: ${e.message}")
            }
        }
    }

    fun setVolume(volume: Float) {
        try {
            audioTrack?.setVolume(volume)
        } catch (e: Exception) {
            Log.e(TAG, "Error adjusting volume: ${e.message}")
        }
    }
}
