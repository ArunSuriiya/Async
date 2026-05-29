import 'dart:async';
import 'package:flutter/services.dart';

class CapturedPacket {
  final int timestamp;
  final Uint8List data;
  final double volume;

  CapturedPacket({
    required this.timestamp,
    required this.data,
    required this.volume,
  });
}

class AudioCaptureManager {
  static const _controlChannel = MethodChannel('com.async.async_share/audio_capture');
  static const _streamChannel = EventChannel('com.async.async_share/audio_capture_stream');
  static const _levelChannel = EventChannel('com.async.async_share/audio_capture_level');

  /// Check if system audio capture is supported on current OS version (Android 10+)
  Future<bool> isCaptureSupported() async {
    try {
      final bool supported = await _controlChannel.invokeMethod('isCaptureSupported');
      return supported;
    } catch (_) {
      return false;
    }
  }

  /// Trigger Android system dialog to request MediaProjection permission.
  /// Returns [true] if permission was granted, [false] otherwise.
  Future<bool> requestPermission() async {
    try {
      final bool granted = await _controlChannel.invokeMethod('requestPermission');
      return granted;
    } catch (e) {
      return false;
    }
  }

  /// Launch foreground audio capture service with projection intent.
  Future<bool> startCapture() async {
    try {
      final bool started = await _controlChannel.invokeMethod('startCapture');
      return started;
    } catch (e) {
      return false;
    }
  }

  /// Terminate background audio capture foreground service.
  Future<bool> stopCapture() async {
    try {
      final bool stopped = await _controlChannel.invokeMethod('stopCapture');
      return stopped;
    } catch (e) {
      return false;
    }
  }

  /// Stream of incoming captured Opus encoded packets from the recorder
  Stream<CapturedPacket> get packetStream {
    return _streamChannel.receiveBroadcastStream().map((event) {
      final map = event as Map;
      return CapturedPacket(
        timestamp: map['timestamp'] as int,
        data: map['data'] as Uint8List,
        volume: (map['volume'] as num?)?.toDouble() ?? 1.0,
      );
    });
  }

  /// Stream of real-time audio levels (range 0.0 to 1.0)
  Stream<double> get levelStream {
    return _levelChannel.receiveBroadcastStream().map((event) => (event as num).toDouble());
  }
}
