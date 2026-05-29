package com.async.async_share

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.*
import android.media.AudioPlaybackCaptureConfiguration
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import io.github.jaredmdobson.concentus.OpusApplication
import io.github.jaredmdobson.concentus.OpusEncoder
import io.github.jaredmdobson.concentus.OpusSignal
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread

class LiveAudioCaptureService : Service() {

    interface AudioCaptureListener {
        fun onAudioPacketEncoded(timestamp: Long, volume: Float, data: ByteArray)
        fun onAudioLevelUpdated(level: Float)
        fun onError(message: String)
    }

    companion object {
        private const val TAG = "LiveAudioCaptureService"
        private const val CHANNEL_ID = "LiveAudioCaptureChannel"
        private const val NOTIFICATION_ID = 9082
        
        var listener: AudioCaptureListener? = null
        var isServiceRunning = false
            private set
    }

    private var mediaProjectionManager: MediaProjectionManager? = null
    private var mediaProjection: MediaProjection? = null
    private var audioRecord: AudioRecord? = null
    private var isRecording = false
    private var recordingThread: Thread? = null
    private var encoder: OpusEncoder? = null

    private var hostVolume = 1.0f
    private var volumeObserver: android.database.ContentObserver? = null

    private fun updateVolumeCache() {
        try {
            val audioManager = getSystemService(android.content.Context.AUDIO_SERVICE) as android.media.AudioManager
            val current = audioManager.getStreamVolume(android.media.AudioManager.STREAM_MUSIC)
            val max = audioManager.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC)
            hostVolume = if (max > 0) current.toFloat() / max else 1.0f
        } catch (e: Exception) {
            Log.e(TAG, "Error updating volume cache: ${e.message}", e)
        }
    }

    override fun onCreate() {
        super.onCreate()
        isServiceRunning = true
        mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        updateVolumeCache()

        volumeObserver = object : android.database.ContentObserver(android.os.Handler(android.os.Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                super.onChange(selfChange)
                updateVolumeCache()
            }
        }
        contentResolver.registerContentObserver(
            android.provider.Settings.System.CONTENT_URI,
            true,
            volumeObserver!!
        )
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val resultCode = intent?.getIntExtra("resultCode", Activity.RESULT_CANCELED) ?: Activity.RESULT_CANCELED
        val resultData = intent?.getParcelableExtra<Intent>("resultData")

        if (resultCode == Activity.RESULT_CANCELED || resultData == null) {
            Log.e(TAG, "No MediaProjection intent data provided, stopping service")
            stopSelf()
            return START_NOT_STICKY
        }

        createNotificationChannel()
        startForegroundServiceNotification()

        try {
            mediaProjection = mediaProjectionManager?.getMediaProjection(resultCode, resultData)
            if (mediaProjection == null) {
                Log.e(TAG, "Failed to obtain MediaProjection")
                listener?.onError("Failed to obtain MediaProjection")
                stopSelf()
                return START_NOT_STICKY
            }

            // Register callback to stop recording if projection stops
            mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    Log.i(TAG, "MediaProjection stopped")
                    stopRecording()
                    stopSelf()
                }
            }, null)

            startRecording()
        } catch (e: Exception) {
            Log.e(TAG, "Error starting capture: ${e.message}", e)
            listener?.onError("Error starting capture: ${e.message}")
            stopSelf()
        }

        return START_NOT_STICKY
    }

    private fun startRecording() {
        if (isRecording) return

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            val err = "Audio playback capture requires Android 10+ (API Q)"
            Log.e(TAG, err)
            listener?.onError(err)
            stopSelf()
            return
        }

        // Configure playback capture
        val projection = mediaProjection ?: return
        val captureConfig = AudioPlaybackCaptureConfiguration.Builder(projection)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()

        val sampleRate = 48000
        val channels = AudioFormat.CHANNEL_IN_MONO
        val encoding = AudioFormat.ENCODING_PCM_16BIT
        
        // 20ms frame at 48kHz mono = 960 samples
        val frameSize = 960
        val minBufferSize = AudioRecord.getMinBufferSize(sampleRate, channels, encoding)
        val bufferSize = Math.max(minBufferSize, frameSize * 4)

        try {
            audioRecord = AudioRecord.Builder()
                .setAudioFormat(AudioFormat.Builder()
                    .setEncoding(encoding)
                    .setSampleRate(sampleRate)
                    .setChannelMask(channels)
                    .build())
                .setAudioPlaybackCaptureConfig(captureConfig)
                .setBufferSizeInBytes(bufferSize)
                .build()

            // Initialize Concentus Opus Encoder
            encoder = OpusEncoder(sampleRate, 1, OpusApplication.OPUS_APPLICATION_AUDIO)
            encoder?.bitrate = 64000 // 64 kbps target
            encoder?.signalType = OpusSignal.OPUS_SIGNAL_MUSIC
            encoder?.complexity = 5 // battery friendly but high quality

            audioRecord?.startRecording()
            isRecording = true

            recordingThread = thread(start = true, name = "AsyncAudioCapture") {
                captureLoop(frameSize)
            }
            Log.i(TAG, "Audio capture recording thread started successfully")
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException creating AudioRecord: ${e.message}")
            listener?.onError("Permission denied: ${e.message}")
            stopSelf()
        } catch (e: Exception) {
            Log.e(TAG, "Exception starting AudioRecord: ${e.message}")
            listener?.onError("Failed to start recorder: ${e.message}")
            stopSelf()
        }
    }

    private fun captureLoop(frameSize: Int) {
        val pcmBuffer = ShortArray(frameSize)
        val opusBuffer = ByteArray(frameSize * 2) // Opus encoded output won't exceed PCM size

        while (isRecording) {
            val record = audioRecord ?: break
            val read = record.read(pcmBuffer, 0, frameSize)

            if (read < 0) {
                Log.e(TAG, "AudioRecord read error: $read")
                listener?.onError("AudioRecord read error: $read")
                break
            }

            if (read > 0) {
                // 1. Calculate real-time audio volume level (RMS)
                var sum = 0.0
                for (i in 0 until read) {
                    sum += pcmBuffer[i] * pcmBuffer[i]
                }
                val rms = Math.sqrt(sum / read)
                val level = (rms / 32768.0).toFloat().coerceIn(0f, 1f)
                listener?.onAudioLevelUpdated(level)

                // 2. Encode to Opus
                try {
                    val encoderRef = encoder
                    if (encoderRef != null) {
                        val encodedLength = encoderRef.encode(pcmBuffer, 0, read, opusBuffer, 0, opusBuffer.size)
                        if (encodedLength > 0) {
                            val encodedPacket = ByteArray(encodedLength)
                            System.arraycopy(opusBuffer, 0, encodedPacket, 0, encodedLength)
                            listener?.onAudioPacketEncoded(System.currentTimeMillis(), hostVolume, encodedPacket)
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Opus encoding failure: ${e.message}")
                }
            }
        }
    }

    private fun stopRecording() {
        isRecording = false
        try {
            audioRecord?.stop()
            audioRecord?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing AudioRecord: ${e.message}")
        }
        audioRecord = null
        recordingThread = null
        encoder = null
    }

    private fun startForegroundServiceNotification() {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Async Live Audio Broadcast")
            .setContentText("Capturing system audio to share...")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Async Live Audio Broadcast Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Foreground Notification for capturing system audio"
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        Log.i(TAG, "Destroying LiveAudioCaptureService")
        stopRecording()
        mediaProjection?.stop()
        mediaProjection = null
        isServiceRunning = false
        volumeObserver?.let {
            contentResolver.unregisterContentObserver(it)
            volumeObserver = null
        }
        super.onDestroy()
    }
}
