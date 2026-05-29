import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import 'live_broadcast_service.dart';

// Provider for Live Broadcast service
final liveBroadcastServiceProvider = ChangeNotifierProvider<LiveBroadcastService>((ref) {
  final websocket = ref.read(websocketServiceProvider);
  final syncEngine = ref.read(syncEngineProvider);
  return LiveBroadcastService(websocket, syncEngine);
});
