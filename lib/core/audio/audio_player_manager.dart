import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../network/http_audio_server.dart';
import '../network/websocket_service.dart';
import '../sync/sync_engine.dart';
import '../utils/network_utils.dart';

class LocalTrack {
  final String id;
  final String title;
  final String artist;
  final String filePath;
  final Duration duration;

  LocalTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.filePath,
    required this.duration,
  });
}

class AudioPlayerManager extends ChangeNotifier {
  final SyncEngine _syncEngine;
  final WebSocketService _wsService;
  final HttpAudioServer _httpServer = HttpAudioServer();

  // Core Audio Players
  late final AudioPlayer _mainPlayer;
  AudioPlayer? _simPlayer; // Player for Virtual Client Simulator

  // Current State
  LocalTrack? _currentTrack;
  bool _isPlaying = false;
  bool _isBuffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Simulator State (for local diagnostic visualization)
  bool _simulatorEnabled = false;
  double _simLatencyMs = 60.0;
  double _simClockOffsetMs = 180.0;
  Duration _simPosition = Duration.zero;
  bool _simIsPlaying = false;
  double _simSpeed = 1.0;
  double _simDriftMs = 0;

  // Timers
  Timer? _hostSyncBroadcastTimer;
  Timer? _driftCorrectionTimer;

  // Volume Sync
  double _lastSystemVolume = 1.0;
  int _lastPeerCount = 0;

  AudioPlayerManager(this._syncEngine, this._wsService) {
    _mainPlayer = AudioPlayer();
    
    // Listen to player streams
    _mainPlayer.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      _isBuffering = state.processingState == ProcessingState.buffering ||
                     state.processingState == ProcessingState.loading;
      notifyListeners();
    });

    _mainPlayer.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _mainPlayer.durationStream.listen((dur) {
      _duration = dur ?? Duration.zero;
      notifyListeners();
    });

    // Wire up WebSocket Client callbacks
    _wsService.onPlayRequested = _onClientPlayRequested;
    _wsService.onPauseRequested = _onClientPauseRequested;
    _wsService.onSeekRequested = _onClientSeekRequested;
    _wsService.onTrackInfoChanged = _onClientTrackInfoChanged;
    _wsService.onVolumeChanged = (vol) {
      _mainPlayer.setVolume(vol);
      notifyListeners();
    };

    // Listen to physical system volume changes and sync to client speakers
    const EventChannel('com.async.async_share/system_volume')
        .receiveBroadcastStream()
        .listen((volume) {
          _lastSystemVolume = (volume as num).toDouble();
          if (_wsService.isHost) {
            _wsService.broadcast({
              'action': 'volume',
              'volume': _lastSystemVolume,
            });
          }
        });

    // Sync volume when new clients connect
    _wsService.addListener(_onWebSocketChanged);
  }

  void _onWebSocketChanged() {
    if (!_wsService.isHost) return;
    
    final currentPeerCount = _wsService.peers.length;
    if (currentPeerCount > _lastPeerCount) {
      // A new peer connected! Send the current system volume.
      debugPrint('[AudioPlayerManager] New client connected. Syncing volume: $_lastSystemVolume');
      _wsService.broadcast({
        'action': 'volume',
        'volume': _lastSystemVolume,
      });
    }
    _lastPeerCount = currentPeerCount;
  }

  // Getters
  AudioPlayer get player => _mainPlayer;
  LocalTrack? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  Duration get position => _position;
  Duration get duration => _duration;

  // Simulator Getters
  bool get simulatorEnabled => _simulatorEnabled;
  Duration get simPosition => _simPosition;
  bool get simIsPlaying => _simIsPlaying;
  double get simSpeed => _simSpeed;
  double get simDriftMs => _simDriftMs;
  double get simLatency => _simLatencyMs;
  double get simOffset => _simClockOffsetMs;

  // --- HOST CONTROLS ---

  /// Host starts playing a track, broadcasting instructions to all peers
  Future<void> hostPlay(LocalTrack track, {int positionMs = 0}) async {
    _currentTrack = track;
    notifyListeners();

    final isWebUrl = track.filePath.startsWith('http://') || track.filePath.startsWith('https://');
    String localUrl;
    String broadcastUrl;

    if (isWebUrl) {
      localUrl = track.filePath;
      broadcastUrl = track.filePath;
    } else {
      // 1. Register track on Host HTTP Server
      if (!_httpServer.isRunning) {
        await _httpServer.start();
      }
      _httpServer.registerTrack(track.id, track.filePath);
      
      // Host plays local file directly using a file URI to avoid cleartext HTTP blocks and reduce latency.
      localUrl = Uri.file(track.filePath).toString();
      final hostLanIp = await NetworkUtils.getLocalWifiIp();
      broadcastUrl = _httpServer.getStreamUrl(hostLanIp, track.id);
    }

    // 2. Prepare Local Player
    await _mainPlayer.setAudioSource(
      AudioSource.uri(
        Uri.parse(localUrl),
        tag: MediaItem(
          id: track.id,
          album: "Async Playlist",
          title: track.title,
          artist: track.artist,
        ),
      ),
    );
    await _mainPlayer.seek(Duration(milliseconds: positionMs));

    // 3. Coordinate Playback Start Time (e.g. 600ms in the future)
    final delayMs = 600;
    final startHostTime = _syncEngine.currentHostTime + delayMs;

    // 4. Broadcast command via WebSocket
    _wsService.broadcast({
      'action': 'play',
      'trackUrl': broadcastUrl,
      'trackId': track.id,
      'title': track.title,
      'artist': track.artist,
      'startHostTime': startHostTime,
      'positionMs': positionMs,
    });

    // 5. Schedule Local Start
    _syncEngine.scheduleTask(startHostTime, () {
      _mainPlayer.play();
      _startHostSyncBroadcastLoop();
    });

    // 6. Handle Simulator Start
    if (_simulatorEnabled) {
      _runSimulatorPlay(broadcastUrl, track, startHostTime, positionMs);
    }
  }

  /// Host pauses playback
  void hostPause() {
    _mainPlayer.pause();
    _wsService.broadcast({'action': 'pause'});
    _stopHostSyncBroadcastLoop();

    if (_simulatorEnabled) {
      _simPlayer?.pause();
      _simIsPlaying = false;
      notifyListeners();
    }
  }

  /// Host seeks to a playhead position
  Future<void> hostSeek(int positionMs) async {
    final delayMs = 400;
    final startHostTime = _syncEngine.currentHostTime + delayMs;

    _wsService.broadcast({
      'action': 'seek',
      'positionMs': positionMs,
      'startHostTime': startHostTime,
    });

    await _mainPlayer.seek(Duration(milliseconds: positionMs));
    _syncEngine.scheduleTask(startHostTime, () {
      if (_isPlaying) _mainPlayer.play();
    });

    if (_simulatorEnabled) {
      _runSimulatorSeek(positionMs, startHostTime);
    }
  }

  /// Sets player volume and, if host, broadcasts it to all speakers
  void setVolume(double val) {
    _mainPlayer.setVolume(val);
    if (_wsService.isHost) {
      _wsService.broadcast({
        'action': 'volume',
        'volume': val,
      });
    }
    notifyListeners();
  }

  // --- CLIENT CALLBACK HANDLERS ---

  Future<void> _onClientPlayRequested(
    String trackUrl,
    int startHostTime,
    int positionMs,
    String trackId,
    String title,
    String artist,
  ) async {
    debugPrint('[Audio Client] Received play command: $trackUrl starting at $startHostTime');
    _currentTrack = LocalTrack(
      id: trackId,
      title: title,
      artist: artist,
      filePath: '',
      duration: Duration.zero,
    );
    notifyListeners();

    // Load stream and seek
    await _mainPlayer.setAudioSource(
      AudioSource.uri(
        Uri.parse(trackUrl),
        tag: MediaItem(
          id: trackId,
          album: "Async Stream",
          title: title,
          artist: artist,
        ),
      ),
    );
    await _mainPlayer.seek(Duration(milliseconds: positionMs));
    await _mainPlayer.pause();

    // Schedule play
    _syncEngine.scheduleTask(startHostTime, () {
      // Determine if we missed the start window
      final nowHostTime = _syncEngine.currentHostTime;
      if (nowHostTime > startHostTime) {
        final catchupMs = nowHostTime - startHostTime;
        final targetPosition = positionMs + catchupMs;
        debugPrint('[Audio Client] Missed sync window by $catchupMs ms, seeking to catchup: $targetPosition ms');
        _mainPlayer.seek(Duration(milliseconds: targetPosition));
      }
      _mainPlayer.play();
      _startDriftCorrectionLoop();
    });
  }

  void _onClientPauseRequested() {
    debugPrint('[Audio Client] Received pause command');
    _mainPlayer.pause();
    _stopDriftCorrectionLoop();
  }

  Future<void> _onClientSeekRequested(int positionMs, int startHostTime) async {
    debugPrint('[Audio Client] Received seek command: $positionMs ms');
    await _mainPlayer.seek(Duration(milliseconds: positionMs));
    _syncEngine.scheduleTask(startHostTime, () {
      if (_isPlaying) _mainPlayer.play();
    });
  }

  void _onClientTrackInfoChanged(String trackId, String title, String artist) {
    _currentTrack = LocalTrack(
      id: trackId,
      title: title,
      artist: artist,
      filePath: '',
      duration: Duration.zero,
    );
    notifyListeners();
  }

  // --- DRIFT CORRECTION ENGINE ---

  /// Host periodically broadcasts its current precise playhead position
  void _startHostSyncBroadcastLoop() {
    _hostSyncBroadcastTimer?.cancel();
    _hostSyncBroadcastTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }
      
      _wsService.broadcast({
        'action': 'sync_check',
        'hostTime': _syncEngine.currentHostTime,
        'positionMs': _mainPlayer.position.inMilliseconds,
      });
    });
  }

  void _stopHostSyncBroadcastLoop() {
    _hostSyncBroadcastTimer?.cancel();
    _hostSyncBroadcastTimer = null;
  }

  /// Client compares local playhead against Host broadcasts and corrects drift
  void _startDriftCorrectionLoop() {
    _driftCorrectionTimer?.cancel();
    
    // Attach listener to WebSocket notifications for manual checks or run a periodic check
    _driftCorrectionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_mainPlayer.playing) return;

      // To keep it simple: we can run drift calculations using the websocket's periodic updates.
      // We will implement drift calculations inside the client listener message handler instead,
      // and use this timer to apply smoothing.
    });

    // Wire sync check parser directly to client socket messages
    _wsService.onPlayRequested = _onClientPlayRequested; // keep bound
  }

  void _stopDriftCorrectionLoop() {
    _driftCorrectionTimer?.cancel();
    _driftCorrectionTimer = null;
    _mainPlayer.setSpeed(1.0); // Reset speed to normal
  }

  /// Handle incoming sync_check messages on the Client to compute drift and apply speed adjustments
  void handleHostSyncCheck(int hostBroadcastTime, int hostPositionMs) {
    if (!_mainPlayer.playing) return;

    final clientNowHostTime = _syncEngine.currentHostTime;
    final timePassedSinceBroadcast = clientNowHostTime - hostBroadcastTime;
    final expectedClientPosition = hostPositionMs + timePassedSinceBroadcast;
    final actualClientPosition = _mainPlayer.position.inMilliseconds;

    final drift = actualClientPosition - expectedClientPosition;
    final absDrift = drift.abs();

    if (absDrift < 15) {
      // Under 15ms is in perfect sync
      _mainPlayer.setSpeed(1.0);
    } else if (absDrift >= 15 && absDrift < 120) {
      // Small/Medium drift: Adjust speed by 2% to smoothly re-align without audio cracking
      if (drift > 0) {
        // Client is running too fast (ahead of Host). Slow down.
        _mainPlayer.setSpeed(0.98);
      } else {
        // Client is running too slow (behind Host). Speed up.
        _mainPlayer.setSpeed(1.02);
      }
    } else {
      // Large drift (>120ms): Perform a hard sync seek
      debugPrint('[Drift Corrector] Large drift detected ($drift ms). Performing hard seek to $expectedClientPosition ms');
      _mainPlayer.seek(Duration(milliseconds: expectedClientPosition));
      _mainPlayer.setSpeed(1.0);
    }
  }

  // --- VIRTUAL CLIENT SIMULATOR CONTROLS ---

  /// Toggle the virtual client simulator on/off
  void toggleSimulator(bool enabled) {
    _simulatorEnabled = enabled;
    if (_simulatorEnabled) {
      _simPlayer = AudioPlayer();
      _simPlayer!.positionStream.listen((pos) {
        _simPosition = pos;
        _runVirtualDriftLoop();
        notifyListeners();
      });
      _simPlayer!.playerStateStream.listen((state) {
        _simIsPlaying = state.playing;
        notifyListeners();
      });
    } else {
      _simPlayer?.dispose();
      _simPlayer = null;
      _simIsPlaying = false;
      _simDriftMs = 0;
      _simSpeed = 1.0;
    }
    notifyListeners();
  }

  /// Configure simulator latency and offset settings
  void updateSimulatorSettings(double latencyMs, double offsetMs) {
    _simLatencyMs = latencyMs;
    _simClockOffsetMs = offsetMs;
    notifyListeners();
  }

  /// Simulate Client receiving the play event with network latency and clock offset
  void _runSimulatorPlay(String streamUrl, LocalTrack track, int startHostTime, int positionMs) {
    if (_simPlayer == null) return;

    // Simulate clock difference:
    // Client's Clock = Host's Clock - _simClockOffsetMs
    final simClientLocalTimeOffset = -_simClockOffsetMs; 

    // Simulate latency before client receives message
    Timer(Duration(milliseconds: _simLatencyMs.round()), () async {
      if (_simPlayer == null) return;
      
      await _simPlayer!.setAudioSource(
        AudioSource.uri(
          Uri.parse(streamUrl),
          tag: MediaItem(
            id: track.id,
            album: "Async Simulator",
            title: track.title,
            artist: track.artist,
          ),
        ),
      );
      await _simPlayer!.seek(Duration(milliseconds: positionMs));
      await _simPlayer!.pause();

      // Client schedules playback at local target time
      final targetClientLocalTime = startHostTime + simClientLocalTimeOffset;
      final localClientNow = DateTime.now().millisecondsSinceEpoch + simClientLocalTimeOffset;
      final delay = targetClientLocalTime - localClientNow;

      if (delay <= 0) {
        final catchup = delay.abs().round();
        await _simPlayer!.seek(Duration(milliseconds: positionMs + catchup));
        _simPlayer!.play();
      } else {
        Timer(Duration(milliseconds: delay.round()), () {
          _simPlayer?.play();
        });
      }
    });
  }

  void _runSimulatorSeek(int positionMs, int startHostTime) {
    if (_simPlayer == null) return;
    
    final simClientLocalTimeOffset = -_simClockOffsetMs;
    Timer(Duration(milliseconds: _simLatencyMs.round()), () async {
      await _simPlayer?.seek(Duration(milliseconds: positionMs));
      
      final targetClientLocalTime = startHostTime + simClientLocalTimeOffset;
      final localClientNow = DateTime.now().millisecondsSinceEpoch + simClientLocalTimeOffset;
      final delay = targetClientLocalTime - localClientNow;

      if (delay <= 0) {
        _simPlayer?.play();
      } else {
        Timer(Duration(milliseconds: delay.round()), () {
          _simPlayer?.play();
        });
      }
    });
  }

  /// Compare simulator position to main player and emulate the drift correction calculations
  void _runVirtualDriftLoop() {
    if (_simPlayer == null || !_simPlayer!.playing || !_mainPlayer.playing) {
      _simDriftMs = 0;
      return;
    }

    // Expected client position (Host position + network latency simulation)
    // For local visualizer, we can compare directly:
    final hostPos = _mainPlayer.position.inMilliseconds;
    final clientPos = _simPlayer!.position.inMilliseconds;

    // Client position - Host position
    final drift = (clientPos - hostPos).toDouble();
    _simDriftMs = drift;

    final absDrift = drift.abs();
    if (absDrift < 15) {
      _simSpeed = 1.0;
      _simPlayer!.setSpeed(1.0);
    } else if (absDrift >= 15 && absDrift < 120) {
      if (drift > 0) {
        _simSpeed = 0.98;
        _simPlayer!.setSpeed(0.98);
      } else {
        _simSpeed = 1.02;
        _simPlayer!.setSpeed(1.02);
      }
    } else {
      // Hard seek
      _simPlayer!.seek(Duration(milliseconds: hostPos));
      _simSpeed = 1.0;
      _simPlayer!.setSpeed(1.0);
    }
  }

  // --- CLEANUP ---

  @override
  void dispose() {
    _wsService.removeListener(_onWebSocketChanged);
    _mainPlayer.dispose();
    _simPlayer?.dispose();
    _httpServer.stop();
    _hostSyncBroadcastTimer?.cancel();
    _driftCorrectionTimer?.cancel();
    super.dispose();
  }
}
