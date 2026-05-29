import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;

enum RoomType {
  LOCAL_SYNC,
  LIVE_BROADCAST
}

class DiscoveredRoom {
  final String name;
  final String ip;
  final int port;
  final String txtRecord;
  final RoomType roomType;

  DiscoveredRoom({
    required this.name,
    required this.ip,
    required this.port,
    required this.txtRecord,
    this.roomType = RoomType.LOCAL_SYNC,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredRoom &&
          runtimeType == other.runtimeType &&
          ip == other.ip &&
          port == other.port &&
          roomType == other.roomType;

  @override
  int get hashCode => ip.hashCode ^ port.hashCode ^ roomType.hashCode;
}

class NetworkDiscoveryService extends ChangeNotifier {
  nsd.Registration? _registration;
  nsd.Discovery? _discovery;
  final Set<DiscoveredRoom> _discoveredRooms = {};
  bool _isScanning = false;

  bool get isAdvertising => _registration != null;
  bool get isScanning => _isScanning;
  List<DiscoveredRoom> get discoveredRooms => _discoveredRooms.toList();

  /// Advertise this room over mDNS / Bonjour
  Future<void> advertiseService(
    String roomName,
    int port, {
    RoomType roomType = RoomType.LOCAL_SYNC,
  }) async {
    await stopAdvertising();

    try {
      debugPrint('[Discovery] Advertising service "_async-music._tcp" on port $port with name "$roomName" ($roomType)');
      _registration = await nsd.register(
        nsd.Service(
          name: roomName,
          type: '_async-music._tcp',
          port: port,
          txt: {
            'room_id': Uint8List.fromList(utf8.encode('async_room_${DateTime.now().millisecondsSinceEpoch}')),
            'room_type': Uint8List.fromList(utf8.encode(roomType.name)),
          },
        ),
      );
      notifyListeners();
    } catch (e) {
      debugPrint('[Discovery] Failed to register service: $e');
      rethrow;
    }
  }

  /// Stop advertising the local room
  Future<void> stopAdvertising() async {
    if (_registration != null) {
      await nsd.unregister(_registration!);
      _registration = null;
      notifyListeners();
      debugPrint('[Discovery] Stopped advertising.');
    }
  }

  /// Start scanning for nearby Async rooms
  Future<void> startScanning() async {
    if (_isScanning) return;
    _discoveredRooms.clear();
    _isScanning = true;
    notifyListeners();

    try {
      debugPrint('[Discovery] Starting discovery for "_async-music._tcp"');
      _discovery = await nsd.startDiscovery('_async-music._tcp');
      
      _discovery!.addListener(() {
        final services = _discovery!.services;
        bool changed = false;

        for (var service in services) {
          final name = service.name ?? 'Async Room';
          final port = service.port;
          
          // nsd package automatically tries to resolve addresses.
          // Let's find the first valid IPv4 address
          String? ip;
          if (service.addresses != null && service.addresses!.isNotEmpty) {
            for (var addr in service.addresses!) {
              if (addr.type == InternetAddressType.IPv4) {
                ip = addr.address;
                break;
              }
            }
            if (ip == null && service.addresses!.isNotEmpty) {
              ip = service.addresses!.first.address;
            }
          }

          if (ip != null && port != null) {
            final txtBytes = service.txt?['room_id'];
            final txtRecord = txtBytes != null ? String.fromCharCodes(txtBytes) : '';
            
            final typeBytes = service.txt?['room_type'];
            final roomTypeStr = typeBytes != null ? String.fromCharCodes(typeBytes) : 'LOCAL_SYNC';
            final roomType = roomTypeStr == 'LIVE_BROADCAST' ? RoomType.LIVE_BROADCAST : RoomType.LOCAL_SYNC;

            final room = DiscoveredRoom(
              name: name,
              ip: ip,
              port: port,
              txtRecord: txtRecord,
              roomType: roomType,
            );

            if (!_discoveredRooms.contains(room)) {
              _discoveredRooms.add(room);
              changed = true;
            }
          }
        }

        if (changed) {
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint('[Discovery] Failed to start discovery: $e');
      _isScanning = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Stop scanning for nearby rooms
  Future<void> stopScanning() async {
    if (!_isScanning) return;
    _isScanning = false;
    
    if (_discovery != null) {
      await nsd.stopDiscovery(_discovery!);
      _discovery = null;
    }
    _discoveredRooms.clear();
    notifyListeners();
    debugPrint('[Discovery] Stopped scanning.');
  }

  /// Probe the hotspot gateway IP directly on port 8081 for Async server info.
  /// If found, adds it to the discovered rooms set so it appears in the room list automatically.
  Future<void> probeAndAddGateway(String gatewayIp) async {
    try {
      debugPrint('[Discovery] Probing hotspot gateway: http://$gatewayIp:8081/info');
      final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 1500);
      final request = await client.getUrl(Uri.parse('http://$gatewayIp:8081/info'));
      final response = await request.close();
      
      if (response.statusCode == HttpStatus.ok) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final roomName = data['roomName'] ?? 'Hotspot Room';
        final port = data['port'] ?? 8081;
        final roomTypeStr = data['roomType'] ?? 'LOCAL_SYNC';
        final roomType = roomTypeStr == 'LIVE_BROADCAST' ? RoomType.LIVE_BROADCAST : RoomType.LOCAL_SYNC;

        final room = DiscoveredRoom(
          name: roomName,
          ip: gatewayIp,
          port: port,
          txtRecord: 'hotspot',
          roomType: roomType,
        );

        if (!_discoveredRooms.contains(room)) {
          _discoveredRooms.add(room);
          notifyListeners();
          debugPrint('[Discovery] Discovered hotspot host room: $roomName at $gatewayIp:$port ($roomType)');
        }
      }
    } catch (e) {
      debugPrint('[Discovery] Gateway probe skipped (no Async host running): $e');
    }
  }

  /// Shutdown both advertisement and scanning
  Future<void> shutdown() async {
    await stopAdvertising();
    await stopScanning();
  }
}
