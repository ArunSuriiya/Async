import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sync/sync_engine.dart';
import 'network/websocket_service.dart';
import 'network/network_discovery_service.dart';
import 'audio/audio_player_manager.dart';

// Sync Engine Provider
final syncEngineProvider = ChangeNotifierProvider<SyncEngine>((ref) {
  return SyncEngine();
});

// WebSocket Service Provider
final websocketServiceProvider = ChangeNotifierProvider<WebSocketService>((ref) {
  final sync = ref.read(syncEngineProvider);
  return WebSocketService(sync);
});

// Network Discovery Service Provider
final discoveryServiceProvider = ChangeNotifierProvider<NetworkDiscoveryService>((ref) {
  return NetworkDiscoveryService();
});

// Audio Player Manager Provider
final audioPlayerManagerProvider = ChangeNotifierProvider<AudioPlayerManager>((ref) {
  final sync = ref.read(syncEngineProvider);
  final ws = ref.read(websocketServiceProvider);
  return AudioPlayerManager(sync, ws);
});
