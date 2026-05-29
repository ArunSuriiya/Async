import 'package:flutter/services.dart';

class NativeAudioPlayer {
  static const _playerChannel = MethodChannel('com.async.async_share/audio_player');

  /// Initialize the native audio track / engine with target format specifications.
  Future<bool> startPlayer({int sampleRate = 48000, int channels = 1}) async {
    try {
      final bool result = await _playerChannel.invokeMethod('startPlayer', {
        'sampleRate': sampleRate,
        'channels': channels,
      });
      return result;
    } catch (_) {
      return false;
    }
  }

  /// Shut down the native player engine and release its resources.
  Future<bool> stopPlayer() async {
    try {
      final bool result = await _playerChannel.invokeMethod('stopPlayer');
      return result;
    } catch (_) {
      return false;
    }
  }

  /// Push an encoded Opus audio packet block to the native player to be decoded and output.
  Future<void> playPacket(Uint8List packetData) async {
    try {
      await _playerChannel.invokeMethod('playPacket', {
        'data': packetData,
      });
    } catch (_) {
      // Ignored: dropped packet/low-latency stream error
    }
  }

  /// Set the playback speed dynamically for drift alignment.
  /// Allowed ranges are typical of time-stretching codecs (e.g. 0.95 to 1.05).
  Future<void> setPlaybackSpeed(double speed) async {
    try {
      await _playerChannel.invokeMethod('setPlaybackSpeed', {
        'speed': speed,
      });
    } catch (_) {
      // Ignored
    }
  }

  /// Set the playback volume level dynamically (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    try {
      await _playerChannel.invokeMethod('setVolume', {
        'volume': volume,
      });
    } catch (_) {
      // Ignored
    }
  }
}
