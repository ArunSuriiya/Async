import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../../../core/sync/sync_engine.dart';
import '../services/native_audio_player.dart';

class AudioPacket {
  final int hostTimestamp;
  final Uint8List data;
  final int localPlayTime;
  final double volume;

  AudioPacket({
    required this.hostTimestamp,
    required this.data,
    required this.localPlayTime,
    required this.volume,
  });
}

class BroadcastSyncEngine extends ChangeNotifier {
  final SyncEngine _syncEngine;
  final NativeAudioPlayer _nativePlayer;

  // Jitter buffer sorted by local target play time
  final SplayTreeMap<int, AudioPacket> _buffer = SplayTreeMap<int, AudioPacket>();

  bool _isRunning = false;
  Timer? _tickTimer;
  double _currentSpeed = 1.0;
  double _lastPlayedVolume = -1.0;

  // Settings
  int targetLatencyMs = 40; // Default target buffering latency in milliseconds

  // Statistics
  double _currentLatencyMs = 0.0;
  int _droppedPackets = 0;

  BroadcastSyncEngine(this._syncEngine, this._nativePlayer);

  bool get isRunning => _isRunning;
  double get currentSpeed => _currentSpeed;
  int get bufferSize => _buffer.length;
  double get currentLatencyMs => _currentLatencyMs;
  int get droppedPackets => _droppedPackets;

  /// Start the playback and decoding engine
  Future<void> start() async {
    if (_isRunning) return;
    _buffer.clear();
    _droppedPackets = 0;
    _currentSpeed = 1.0;
    _currentLatencyMs = targetLatencyMs.toDouble();

    // Initialize native player with 48kHz mono format
    await _nativePlayer.startPlayer(sampleRate: 48000, channels: 1);
    await _nativePlayer.setPlaybackSpeed(1.0);

    _isRunning = true;

    // High-precision clock tick: runs every 10ms to schedule PCM delivery
    _tickTimer = Timer.periodic(const Duration(milliseconds: 10), _onPlaybackTick);
    notifyListeners();
  }

  /// Stop the playback and decoding engine
  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    _tickTimer?.cancel();
    _tickTimer = null;
    _buffer.clear();
    await _nativePlayer.stopPlayer();
    notifyListeners();
  }

  /// Add an incoming Opus packet to the jitter buffer
  void addPacket(int hostTimestamp, double volume, Uint8List data) {
    if (!_isRunning) return;

    final clockOffset = _syncEngine.clockOffsetMs;
    // Compute local play time: HostTime - Offset + TargetLatency
    final localPlayTime = (hostTimestamp - clockOffset + targetLatencyMs).round();

    final localNow = DateTime.now().millisecondsSinceEpoch;

    // If the packet has arrived too late (> 40ms past its target local play time), drop it
    if (localNow > localPlayTime + 40) {
      _droppedPackets++;
      return;
    }

    final packet = AudioPacket(
      hostTimestamp: hostTimestamp,
      data: data,
      localPlayTime: localPlayTime,
      volume: volume,
    );

    // Store in buffer, automatically sorted by key (localPlayTime)
    _buffer[localPlayTime] = packet;
  }

  /// High-precision ticking playback coordinator
  void _onPlaybackTick(Timer timer) {
    if (!_isRunning) return;

    final localNow = DateTime.now().millisecondsSinceEpoch;

    // 1. Play all packets whose target time has arrived
    final toPlay = <AudioPacket>[];
    final keysToRemove = <int>[];

    for (var key in _buffer.keys) {
      if (localNow >= key) {
        toPlay.add(_buffer[key]!);
        keysToRemove.add(key);
      } else {
        break; // Map is sorted, if this key is in the future, all remaining ones are too
      }
    }

    for (var key in keysToRemove) {
      _buffer.remove(key);
    }

    if (toPlay.isNotEmpty) {
      for (var packet in toPlay) {
        if (packet.volume != _lastPlayedVolume) {
          _lastPlayedVolume = packet.volume;
          _nativePlayer.setVolume(_lastPlayedVolume);
        }
        _nativePlayer.playPacket(packet.data);

        // Update real-time latency metric (current host time - packet host time)
        final packetHostAge = _syncEngine.currentHostTime - packet.hostTimestamp;
        _currentLatencyMs = packetHostAge.toDouble();
      }
      notifyListeners();
    }

    // 2. Perform drift correction speed adjustments every 100ms
    if (localNow % 100 < 10) {
      _adjustPlaybackSpeed();
    }
  }

  /// Update target buffering latency dynamically
  void updateTargetLatency(int latencyMs) {
    if (latencyMs < 30 || latencyMs > 300) return;
    targetLatencyMs = latencyMs;
    notifyListeners();
  }

  /// Adjust hardware playback speed dynamically based on jitter buffer levels
  void _adjustPlaybackSpeed() {
    final size = _buffer.length;
    double newSpeed = 1.0;

    // 20ms per packet
    final int targetPackets = (targetLatencyMs / 20).round().clamp(1, 15);

    // Apply a dead-band zone around the target packet count to prevent audio frequency oscillation
    if (size > targetPackets + 1) {
      // Jitter buffer is growing (backlog): speed up gently to catch up
      newSpeed = 1.015; // 1.5% speedup is practically imperceptible
    } else if (size < targetPackets - 1 && size > 0) {
      // Jitter buffer is starving (empty): slow down gently to allow accumulation
      newSpeed = 0.985; // 1.5% slowdown
    } else {
      // Normal buffer occupancy (within the dead-band zone)
      newSpeed = 1.0;
    }

    if (newSpeed != _currentSpeed) {
      _currentSpeed = newSpeed;
      _nativePlayer.setPlaybackSpeed(_currentSpeed);
      notifyListeners();
    }
  }
}
