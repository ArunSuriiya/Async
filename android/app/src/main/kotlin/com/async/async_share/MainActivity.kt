package com.async.async_share

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val CAPTURE_CHANNEL = "com.async.async_share/audio_capture"
    private val CAPTURE_STREAM_CHANNEL = "com.async.async_share/audio_capture_stream"
    private val CAPTURE_LEVEL_CHANNEL = "com.async.async_share/audio_capture_level"
    private val PLAYER_CHANNEL = "com.async.async_share/audio_player"

    private val PERMISSION_CODE = 1002
    private var permissionResult: MethodChannel.Result? = null
    private var mediaProjectionIntent: Intent? = null

    private var packetSink: EventChannel.EventSink? = null
    private var levelSink: EventChannel.EventSink? = null
    private val liveAudioPlayer = LiveAudioPlayer()

    private var systemVolumeSink: EventChannel.EventSink? = null
    private var volumeObserver: android.database.ContentObserver? = null

    private fun sendCurrentVolume() {
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            val current = audioManager.getStreamVolume(android.media.AudioManager.STREAM_MUSIC)
            val max = audioManager.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC)
            val volumeFraction = if (max > 0) current.toDouble() / max else 1.0
            runOnUiThread {
                systemVolumeSink?.success(volumeFraction)
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error sending system volume: ${e.message}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Audio Capture Control Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAPTURE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isCaptureSupported" -> {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                }
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        result.error("UNSUPPORTED", "Audio capture requires Android 10+", null)
                        return@setMethodCallHandler
                    }
                    permissionResult = result
                    val mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    startActivityForResult(mediaProjectionManager.createScreenCaptureIntent(), PERMISSION_CODE)
                }
                "startCapture" -> {
                    if (mediaProjectionIntent == null) {
                        result.error("NO_PERMISSION", "MediaProjection permission was not obtained yet", null)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(this, LiveAudioCaptureService::class.java).apply {
                        putExtra("resultCode", Activity.RESULT_OK)
                        putExtra("resultData", mediaProjectionIntent)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopCapture" -> {
                    stopService(Intent(this, LiveAudioCaptureService::class.java))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 2. Audio Capture Data Stream (PCM -> Opus -> Standard EventChannel)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CAPTURE_STREAM_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                packetSink = events
            }
            override fun onCancel(arguments: Any?) {
                packetSink = null
            }
        })

        // 3. Audio Capture Volume Level Stream
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CAPTURE_LEVEL_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                levelSink = events
            }
            override fun onCancel(arguments: Any?) {
                levelSink = null
            }
        })

        // 4. Audio Player Channel (Playback management on listener device)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLAYER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startPlayer" -> {
                    val sampleRate = call.argument<Int>("sampleRate") ?: 48000
                    val channels = call.argument<Int>("channels") ?: 1
                    liveAudioPlayer.start(sampleRate, channels)
                    result.success(true)
                }
                "stopPlayer" -> {
                    liveAudioPlayer.stop()
                    result.success(true)
                }
                "playPacket" -> {
                    val data = call.argument<ByteArray>("data")
                    if (data != null) {
                        liveAudioPlayer.playPacket(data)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Audio packet data cannot be null", null)
                    }
                }
                "setPlaybackSpeed" -> {
                    val speed = (call.argument<Double>("speed") ?: 1.0).toFloat()
                    liveAudioPlayer.setPlaybackSpeed(speed)
                    result.success(true)
                }
                "setVolume" -> {
                    val volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
                    liveAudioPlayer.setVolume(volume)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Pipe capture listener notifications into flutter EventSinks
        LiveAudioCaptureService.listener = object : LiveAudioCaptureService.AudioCaptureListener {
            override fun onAudioPacketEncoded(timestamp: Long, volume: Float, data: ByteArray) {
                runOnUiThread {
                    packetSink?.success(mapOf(
                        "timestamp" to timestamp,
                        "volume" to volume.toDouble(),
                        "data" to data
                    ))
                }
            }

            override fun onAudioLevelUpdated(level: Float) {
                runOnUiThread {
                    levelSink?.success(level.toDouble()) // Standard Flutter StandardMessageCodec uses Double for floating point
                }
            }

            override fun onError(message: String) {
                runOnUiThread {
                    packetSink?.error("CAPTURE_ERROR", message, null)
                }
            }
        }
        // 5. System Volume Event Channel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.async.async_share/system_volume").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                systemVolumeSink = events
                sendCurrentVolume()

                if (volumeObserver == null) {
                    volumeObserver = object : android.database.ContentObserver(android.os.Handler(android.os.Looper.getMainLooper())) {
                        override fun onChange(selfChange: Boolean) {
                            super.onChange(selfChange)
                            sendCurrentVolume()
                        }
                    }
                    contentResolver.registerContentObserver(
                        android.provider.Settings.System.CONTENT_URI,
                        true,
                        volumeObserver!!
                    )
                }
            }
            override fun onCancel(arguments: Any?) {
                systemVolumeSink = null
                volumeObserver?.let {
                    contentResolver.unregisterContentObserver(it)
                    volumeObserver = null
                }
            }
        })
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PERMISSION_CODE) {
            val result = permissionResult
            permissionResult = null
            if (resultCode == Activity.RESULT_OK && data != null) {
                mediaProjectionIntent = data
                result?.success(true)
            } else {
                result?.success(false)
            }
        }
    }

    override fun onDestroy() {
        liveAudioPlayer.stop()
        stopService(Intent(this, LiveAudioCaptureService::class.java))
        volumeObserver?.let {
            contentResolver.unregisterContentObserver(it)
            volumeObserver = null
        }
        super.onDestroy()
    }
}
