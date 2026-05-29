import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../sync/sync_engine.dart';
import 'network_discovery_service.dart';

class PeerInfo {
  final String id;
  final String name;
  final String deviceType;
  double latencyMs;
  double offsetMs;
  String playbackState; // 'idle', 'buffering', 'playing', 'paused'
  int positionMs;

  PeerInfo({
    required this.id,
    required this.name,
    required this.deviceType,
    this.latencyMs = 0,
    this.offsetMs = 0,
    this.playbackState = 'idle',
    this.positionMs = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'deviceType': deviceType,
    'latencyMs': latencyMs,
    'offsetMs': offsetMs,
    'playbackState': playbackState,
    'positionMs': positionMs,
  };
}

class WebSocketService extends ChangeNotifier {
  final SyncEngine _syncEngine;

  // Server (Host) fields
  HttpServer? _server;
  final Set<WebSocket> _clientSockets = {};
  final Map<WebSocket, PeerInfo> _peers = {};
  String? _hostUsername;
  RoomType _roomType = RoomType.LOCAL_SYNC;

  // Client fields
  WebSocket? _clientSocket;
  bool _isConnected = false;
  String? _hostIp;
  int? _hostPort;
  
  // Callbacks for the UI and Audio Player Manager to listen to
  void Function(String trackUrl, int startHostTime, int positionMs, String trackId, String title, String artist)? onPlayRequested;
  void Function()? onPauseRequested;
  void Function(int positionMs, int startHostTime)? onSeekRequested;
  void Function(String trackId, String title, String artist)? onTrackInfoChanged;
  void Function(double volume)? onVolumeChanged;
  void Function(Uint8List packet)? onAudioPacketReceived;

  WebSocketService(this._syncEngine);

  bool get isHost => _server != null;
  bool get isConnected => _isConnected || isHost;
  List<PeerInfo> get peers => _peers.values.toList();
  String? get hostIp => _hostIp;
  int? get hostPort => _hostPort;

  // --- HOST SERVICE ---

  /// Start Host WebSocket Server
  Future<int> startServer({required String username, RoomType roomType = RoomType.LOCAL_SYNC}) async {
    await stop();
    _syncEngine.setAsHost();
    _hostUsername = username;
    _roomType = roomType;

    try {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, 8081);
      } catch (e) {
        debugPrint('[WS Server] Port 8081 occupied, falling back to random port: $e');
        _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      }
      _hostPort = _server!.port;
      
      _server!.listen((HttpRequest request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          _handleNewClient(socket);
        } else if (request.method == 'GET' && request.uri.path == '/info') {
          request.response.headers.contentType = ContentType.json;
          request.response.headers.add('Access-Control-Allow-Origin', '*');
          request.response.write(jsonEncode({
            'roomName': '$_hostUsername Room',
            'port': _hostPort,
            'roomType': _roomType.name,
          }));
          await request.response.close();
        } else {
          request.response.statusCode = HttpStatus.forbidden;
          await request.response.close();
        }
      });

      debugPrint('[WS Server] Running on port $_hostPort');
      notifyListeners();
      return _hostPort!;
    } catch (e) {
      debugPrint('[WS Server] Failed to start: $e');
      rethrow;
    }
  }

  void _handleNewClient(WebSocket socket) {
    _clientSockets.add(socket);
    debugPrint('[WS Server] New client connected');

    socket.listen(
      (message) {
        if (message is List<int>) {
          // Ignore binary data uploads from clients
          return;
        }
        _onServerMessageReceived(socket, message);
      },
      onDone: () => _removeClient(socket),
      onError: (e) {
        debugPrint('[WS Server] Client socket error: $e');
        _removeClient(socket);
      },
    );
  }

  void _onServerMessageReceived(WebSocket socket, dynamic message) {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final action = data['action'] as String?;

      if (action == 'sync_ping') {
        final clientT1 = data['t1'] as int;
        final hostNow = DateTime.now().millisecondsSinceEpoch;
        
        socket.add(jsonEncode({
          'action': 'sync_pong',
          't1': clientT1,
          't2': hostNow,
          't3': hostNow,
        }));
      } else if (action == 'identify') {
        final peer = PeerInfo(
          id: data['id'] ?? 'unknown',
          name: data['name'] ?? 'Client Device',
          deviceType: data['deviceType'] ?? 'Unknown',
        );
        _peers[socket] = peer;
        notifyListeners();
      } else if (action == 'status_update') {
        final peer = _peers[socket];
        if (peer != null) {
          peer.latencyMs = (data['latencyMs'] as num?)?.toDouble() ?? 0;
          peer.offsetMs = (data['offsetMs'] as num?)?.toDouble() ?? 0;
          peer.playbackState = data['playbackState'] ?? 'idle';
          peer.positionMs = (data['positionMs'] as num?)?.toInt() ?? 0;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[WS Server] Error parsing client message: $e');
    }
  }

  void _removeClient(WebSocket socket) {
    _clientSockets.remove(socket);
    _peers.remove(socket);
    socket.close();
    notifyListeners();
    debugPrint('[WS Server] Client disconnected. Active peers: ${_clientSockets.length}');
  }

  /// Broadcast message to all connected clients
  void broadcast(Map<String, dynamic> message) {
    final rawJson = jsonEncode(message);
    for (var socket in _clientSockets) {
      socket.add(rawJson);
    }
  }

  /// Broadcast binary packet to all connected clients
  void broadcastBinary(List<int> bytes) {
    for (var socket in _clientSockets) {
      socket.add(bytes);
    }
  }

  // --- CLIENT SERVICE ---

  /// Connect to Host WebSocket Server
  Future<void> connectToHost(String ip, int port, String clientName, String clientId) async {
    await stop();
    _hostIp = ip;
    _hostPort = port;

    try {
      final wsUrl = 'ws://$ip:$port';
      debugPrint('[WS Client] Connecting to $wsUrl ...');
      
      _clientSocket = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 5));
      _isConnected = true;
      notifyListeners();

      // Identify client to host
      sendIdentify(clientId, clientName);

      _clientSocket!.listen(
        _onClientMessageReceived,
        onDone: () => _handleDisconnect(),
        onError: (e) {
          debugPrint('[WS Client] Connection error: $e');
          _handleDisconnect();
        },
      );

      // Start periodic sync ping loop
      _startSyncPings();
      _startStatusUpdates(clientId, clientName);
    } catch (e) {
      debugPrint('[WS Client] Connection failed: $e');
      _isConnected = false;
      notifyListeners();
      rethrow;
    }
  }

  void _onClientMessageReceived(dynamic message) {
    if (message is List<int>) {
      onAudioPacketReceived?.call(Uint8List.fromList(message));
      return;
    }
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final action = data['action'] as String?;

      if (action == 'sync_pong') {
        final t1 = data['t1'] as int;
        final t2 = data['t2'] as int;
        final t3 = data['t3'] as int;
        final t4 = DateTime.now().millisecondsSinceEpoch;

        _syncEngine.calculateNtpOffset(t1: t1, t2: t2, t3: t3, t4: t4);
      } else if (action == 'play') {
        if (onPlayRequested != null) {
          onPlayRequested!(
            data['trackUrl'],
            data['startHostTime'],
            data['positionMs'] ?? 0,
            data['trackId'] ?? '',
            data['title'] ?? 'Unknown',
            data['artist'] ?? 'Unknown',
          );
        }
      } else if (action == 'pause') {
        if (onPauseRequested != null) {
          onPauseRequested!();
        }
      } else if (action == 'seek') {
        if (onSeekRequested != null) {
          onSeekRequested!(
            data['positionMs'],
            data['startHostTime'],
          );
        }
      } else if (action == 'track_info') {
        if (onTrackInfoChanged != null) {
          onTrackInfoChanged!(
            data['trackId'] ?? '',
            data['title'] ?? 'Unknown',
            data['artist'] ?? 'Unknown',
          );
        }
      } else if (action == 'volume') {
        if (onVolumeChanged != null) {
          onVolumeChanged!((data['volume'] as num).toDouble());
        }
      }
    } catch (e) {
      debugPrint('[WS Client] Error parsing server message: $e');
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _clientSocket = null;
    _syncEngine.reset();
    notifyListeners();
    debugPrint('[WS Client] Disconnected from server.');
  }

  void sendIdentify(String id, String name) {
    if (_clientSocket == null) return;
    _clientSocket!.add(jsonEncode({
      'action': 'identify',
      'id': id,
      'name': name,
      'deviceType': Platform.isAndroid ? 'Android' : 'iOS',
    }));
  }

  Timer? _syncTimer;
  void _startSyncPings() {
    _syncTimer?.cancel();
    // Run NTP sync checks: 5 pings quickly to establish start baseline
    int burstCount = 0;
    _syncTimer = Timer.periodic(const Duration(milliseconds: 400), (timer) {
      if (!_isConnected || _clientSocket == null) {
        timer.cancel();
        return;
      }
      _sendPing();
      burstCount++;
      if (burstCount >= 8) {
        timer.cancel();
        // Transition to standard interval pinging (every 5 seconds)
        _syncTimer = Timer.periodic(const Duration(seconds: 5), (t) {
          if (!_isConnected || _clientSocket == null) {
            t.cancel();
            return;
          }
          _sendPing();
        });
      }
    });
  }

  void _sendPing() {
    if (_clientSocket == null) return;
    _clientSocket!.add(jsonEncode({
      'action': 'sync_ping',
      't1': DateTime.now().millisecondsSinceEpoch,
    }));
  }

  Timer? _statusTimer;
  void _startStatusUpdates(String clientId, String clientName) {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_isConnected || _clientSocket == null) {
        timer.cancel();
        return;
      }
      
      // Send diagnostic metadata to Host
      _clientSocket!.add(jsonEncode({
        'action': 'status_update',
        'id': clientId,
        'name': clientName,
        'latencyMs': _syncEngine.networkLatencyMs,
        'offsetMs': _syncEngine.clockOffsetMs,
        // UI or Player status will update these in reality. We send general values
        'playbackState': 'connected',
        'positionMs': 0,
      }));
    });
  }

  // --- GENERAL CONTROLS ---

  /// Shut down everything (either Host server or Client socket)
  Future<void> stop() async {
    _syncTimer?.cancel();
    _statusTimer?.cancel();
    
    // Stop server
    for (var socket in _clientSockets) {
      await socket.close();
    }
    _clientSockets.clear();
    _peers.clear();
    await _server?.close(force: true);
    _server = null;

    // Stop client
    await _clientSocket?.close();
    _clientSocket = null;
    _isConnected = false;
    
    _hostIp = null;
    _hostPort = null;

    notifyListeners();
  }
}
