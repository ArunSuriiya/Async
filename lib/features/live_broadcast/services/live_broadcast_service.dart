import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../../core/network/websocket_service.dart';
import '../../../core/network/network_discovery_service.dart';
import '../../../core/sync/sync_engine.dart';
import '../synchronization/broadcast_sync_engine.dart';
import '../synchronization/latency_monitor.dart';
import 'audio_capture_manager.dart';
import 'audio_level_analyzer.dart';
import 'native_audio_player.dart';

class LiveBroadcastService extends ChangeNotifier {
  final WebSocketService _websocketService;
  final SyncEngine _syncEngine;
  
  final AudioCaptureManager _captureManager = AudioCaptureManager();
  final NativeAudioPlayer _nativePlayer = NativeAudioPlayer();
  late final BroadcastSyncEngine _syncEngineClient;
  
  final AudioLevelAnalyzer hostLevelAnalyzer = AudioLevelAnalyzer();
  final AudioLevelAnalyzer clientLevelAnalyzer = AudioLevelAnalyzer();
  final LatencyMonitor latencyMonitor = LatencyMonitor();

  // Lifecycle States
  bool _isHosting = false;
  bool _isListening = false;
  int _broadcastDurationSecs = 0;
  double _currentBitrateKbps = 0.0;
  
  // Timers and Subscriptions
  Timer? _statsTimer;
  StreamSubscription<CapturedPacket>? _hostPacketSubscription;
  StreamSubscription<double>? _hostLevelSubscription;
  
  int _totalBytesInWindow = 0;
  DateTime? _broadcastStartTime;

  LiveBroadcastService(this._websocketService, this._syncEngine) {
    _syncEngineClient = BroadcastSyncEngine(_syncEngine, _nativePlayer);
    _syncEngineClient.addListener(notifyListeners);
  }

  // Getters
  bool get isHosting => _isHosting;
  bool get isListening => _isListening;
  int get broadcastDurationSecs => _broadcastDurationSecs;
  double get currentBitrateKbps => _currentBitrateKbps;
  int get listenerCount => _websocketService.peers.length;
  double get averageLatencyMs => _isHosting ? 0.0 : latencyMonitor.averageLatencyMs;
  double get jitterMs => _isHosting ? 0.0 : latencyMonitor.jitterMs;
  double get volumeLevel => _isHosting ? hostLevelAnalyzer.smoothedVolume : clientLevelAnalyzer.smoothedVolume;
  BroadcastSyncEngine get syncEngineClient => _syncEngineClient;

  // --- HOST BROADCAST OPERATIONS ---

  /// Request media projection and boot foreground system capture + server broadcast
  Future<bool> startHostBroadcast(String username) async {
    if (_isHosting) return true;

    // 1. Request MediaProjection permissions (Android Only)
    final isSupported = await _captureManager.isCaptureSupported();
    if (!isSupported) {
      debugPrint('[Broadcast Host] System audio capture is not supported on this device version');
      return false;
    }

    final permissionGranted = await _captureManager.requestPermission();
    if (!permissionGranted) {
      debugPrint('[Broadcast Host] MediaProjection permission denied');
      return false;
    }

    try {
      // 2. Start WebSocket Server with LIVE_BROADCAST RoomType
      await _websocketService.startServer(
        username: username, 
        roomType: RoomType.LIVE_BROADCAST
      );

      // 3. Trigger native capture service
      final captureStarted = await _captureManager.startCapture();
      if (!captureStarted) {
        await _websocketService.stop();
        return false;
      }

      _isHosting = true;
      _broadcastStartTime = DateTime.now();
      _broadcastDurationSecs = 0;
      _totalBytesInWindow = 0;
      _currentBitrateKbps = 0.0;

      // 4. Listen to captured audio packets and broadcast over WebSocket
      _hostPacketSubscription = _captureManager.packetStream.listen((CapturedPacket packet) {
        if (!_isHosting) return;

        // Packet size: 8 bytes (long timestamp) + 1 byte (volume) + Opus payload bytes
        final payload = packet.data;
        final packetData = Uint8List(9 + payload.length);
        final byteData = ByteData.sublistView(packetData);
        
        // Write host timestamp in big endian format
        byteData.setInt64(0, packet.timestamp, Endian.big);
        // Write volume factor clamped between 0 and 100 as integer byte
        packetData[8] = (packet.volume * 100).round().clamp(0, 100);
        packetData.setRange(9, packetData.length, payload);

        // Track stats
        _totalBytesInWindow += packetData.length;

        // Broadcast binary packet to all connected sockets
        _websocketService.broadcastBinary(packetData);
      });

      // 5. Connect volume meter stream to host analyzer
      hostLevelAnalyzer.startListening(_captureManager.levelStream);

      // 6. Launch stats timer (1s interval)
      _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _broadcastDurationSecs = DateTime.now().difference(_broadcastStartTime!).inSeconds;
        
        // Compute bitrate: bytes * 8 bits / 1024 to get kbps
        _currentBitrateKbps = (_totalBytesInWindow * 8) / 1024.0;
        _totalBytesInWindow = 0;
        
        notifyListeners();
      });

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[Broadcast Host] Failed to start broadcast session: $e');
      await stopHostBroadcast();
      return false;
    }
  }

  /// Terminate the host recording service and stop server
  Future<void> stopHostBroadcast() async {
    if (!_isHosting) return;
    _isHosting = false;

    _statsTimer?.cancel();
    _statsTimer = null;

    await _hostPacketSubscription?.cancel();
    _hostPacketSubscription = null;

    hostLevelAnalyzer.stopListening();
    await _captureManager.stopCapture();
    await _websocketService.stop();

    _broadcastDurationSecs = 0;
    _currentBitrateKbps = 0.0;
    notifyListeners();
  }

  // --- CLIENT BROADCAST OPERATIONS ---

  /// Connect to Host live stream and begin audio playback
  Future<void> startClientPlayback() async {
    if (_isListening) return;

    try {
      _isListening = true;
      _broadcastStartTime = DateTime.now();
      _broadcastDurationSecs = 0;
      _totalBytesInWindow = 0;
      _currentBitrateKbps = 0.0;
      latencyMonitor.reset();

      // 1. Initialize Sync Engine
      await _syncEngineClient.start();

      // 2. Wire up WebSocket binary packet handler
      _websocketService.onAudioPacketReceived = (Uint8List packet) {
        if (!_isListening) return;

        if (packet.length < 9) return;

        // Extract host timestamp, volume, and Opus payload
        final byteData = ByteData.sublistView(packet);
        final hostTimestamp = byteData.getInt64(0, Endian.big);
        final volume = packet[8] / 100.0;
        final opusData = Uint8List.sublistView(packet, 9);

        _totalBytesInWindow += packet.length;

        // Feed to Jitter Buffer playback engine
        _syncEngineClient.addPacket(hostTimestamp, volume, opusData);

        // Record latency (current host time - packet capture time)
        final hostNow = _syncEngine.currentHostTime;
        final latency = (hostNow - hostTimestamp).toDouble();
        latencyMonitor.recordLatency(latency);
      };

      // 3. Compute client-side audio volume levels based on synchronization queue activity
      // We simulate or estimate volume levels based on packet arrival to feed client animation
      _hostLevelSubscription = _websocketService.onAudioPacketReceived == null 
          ? null 
          : Stream.periodic(const Duration(milliseconds: 50)).map((_) {
              // Extract volume simulation based on buffer fullness
              return _syncEngineClient.bufferSize > 0 ? 0.35 + (_syncEngineClient.bufferSize * 0.05).clamp(0.0, 0.6) : 0.0;
            }).listen((val) {
              clientLevelAnalyzer.updateLevel(val);
            });

      // 4. Launch statistics timer
      _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _broadcastDurationSecs = DateTime.now().difference(_broadcastStartTime!).inSeconds;
        _currentBitrateKbps = (_totalBytesInWindow * 8) / 1024.0;
        _totalBytesInWindow = 0;
        notifyListeners();
      });

      notifyListeners();
    } catch (e) {
      debugPrint('[Broadcast Client] Failed to connect to stream: $e');
      await stopClientPlayback();
    }
  }

  /// Stop audio playback and close engine
  Future<void> stopClientPlayback() async {
    if (!_isListening) return;
    _isListening = false;

    _statsTimer?.cancel();
    _statsTimer = null;

    _websocketService.onAudioPacketReceived = null;
    await _hostLevelSubscription?.cancel();
    _hostLevelSubscription = null;

    clientLevelAnalyzer.stopListening();
    latencyMonitor.reset();
    await _syncEngineClient.stop();

    _broadcastDurationSecs = 0;
    _currentBitrateKbps = 0.0;
    notifyListeners();
  }

  @override
  void dispose() {
    stopHostBroadcast();
    stopClientPlayback();
    _syncEngineClient.removeListener(notifyListeners);
    super.dispose();
  }
}
