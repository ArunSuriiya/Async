import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/theme/theme.dart';
import '../../core/providers.dart';
import '../dashboard/dashboard_screen.dart';
import '../player/now_playing_screen.dart';
import '../../core/audio/audio_player_manager.dart';
import '../../core/network/websocket_service.dart';
import '../../core/network/network_discovery_service.dart';
import '../../core/utils/network_utils.dart';
import '../../core/audio/local_music_provider.dart';
import '../live_broadcast/presentation/broadcast_host_console.dart';
import '../live_broadcast/presentation/broadcast_listener_screen.dart';
import '../live_broadcast/services/providers.dart';

class RoomScreen extends ConsumerStatefulWidget {
  final bool isHost;
  final RoomType roomType;

  const RoomScreen({
    Key? key,
    required this.isHost,
    this.roomType = RoomType.LOCAL_SYNC,
  }) : super(key: key);

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  bool _isLoading = true;
  String _localIp = '127.0.0.1';
  int _port = 8081;
  String _statusMessage = 'Initializing...';
  


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isHost) {
        _setupHostRoom();
      } else {
        _startClientDiscovery();
      }
    });
  }

  Future<void> _setupHostRoom() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Configuring local servers...';
    });

    try {
      // 1. Get Local IP Address
      _localIp = await NetworkUtils.getLocalWifiIp();

      // 2. Start WebSocket Server and Advertise
      final username = ref.read(usernameProvider);
      final wsService = ref.read(websocketServiceProvider);
      final discovery = ref.read(discoveryServiceProvider);

      if (widget.roomType == RoomType.LIVE_BROADCAST) {
        _port = await wsService.startServer(username: username, roomType: RoomType.LIVE_BROADCAST);
        await discovery.advertiseService('$username Room', _port, roomType: RoomType.LIVE_BROADCAST);

        // Start system audio capture & broadcasting
        final broadcastService = ref.read(liveBroadcastServiceProvider);
        final started = await broadcastService.startHostBroadcast(username);
        if (!started) {
          throw Exception('Failed to start system audio capture service.');
        }
      } else {
        _port = await wsService.startServer(username: username, roomType: RoomType.LOCAL_SYNC);
        await discovery.advertiseService('$username Room', _port, roomType: RoomType.LOCAL_SYNC);
      }

      setState(() {
        _isLoading = false;
        _statusMessage = 'Active & Broadcasting';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Failed to setup Host Room: $e';
      });
    }
  }

  void _startClientDiscovery() async {
    ref.read(discoveryServiceProvider).startScanning();
    final ip = await NetworkUtils.getLocalWifiIp();
    setState(() {
      _localIp = ip;
      _isLoading = false;
      _statusMessage = 'Scanning for nearby rooms...';
    });

    final gateway = _getGatewayIp();
    if (gateway != null) {
      ref.read(discoveryServiceProvider).probeAndAddGateway(gateway);
    }
  }

  String? _getGatewayIp() {
    if (_localIp == '127.0.0.1' || _localIp.contains('Offline') || !_localIp.contains('.')) {
      return null;
    }
    final parts = _localIp.split('.');
    if (parts.length == 4) {
      return '${parts[0]}.${parts[1]}.${parts[2]}.1';
    }
    return null;
  }

  @override
  void dispose() {
    // If exiting Room screen, clean up services if not already playing
    final playerManager = ref.read(audioPlayerManagerProvider);
    final wsService = ref.read(websocketServiceProvider);
    final discoveryService = ref.read(discoveryServiceProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!playerManager.isPlaying) {
        wsService.stop();
        discoveryService.shutdown();
      }
    });
    super.dispose();
  }

  Future<void> _pickLocalFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = result.files.single;
        final customTrack = LocalTrack(
          id: 'local_${DateTime.now().millisecondsSinceEpoch}',
          title: file.name.replaceAll('.mp3', ''),
          artist: 'Local File',
          filePath: file.path!,
          duration: Duration(milliseconds: file.size), // temporary estimate
        );

        // Open Player Screen with this track
        _playTrack(customTrack);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking file: $e')),
      );
    }
  }

  void _playTrack(LocalTrack track) async {
    final playerManager = ref.read(audioPlayerManagerProvider);
    
    // Set loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: CyberTheme.neonPink),
      ),
    );

    try {
      await playerManager.hostPlay(track);
      Navigator.pop(context); // Close loading dialog
      
      // Navigate to player
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const NowPlayingScreen(),
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting playback: $e')),
      );
    }
  }

  void _joinDiscoveredRoom(String ip, int port, String roomName, {RoomType roomType = RoomType.LOCAL_SYNC}) async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Connecting to $roomName...';
    });

    try {
      final wsService = ref.read(websocketServiceProvider);
      final username = ref.read(usernameProvider);
      final clientId = ref.read(clientIdProvider);

      await wsService.connectToHost(ip, port, username, clientId);
      
      // Stop mDNS scanning once connected
      ref.read(discoveryServiceProvider).stopScanning();

      if (roomType == RoomType.LIVE_BROADCAST) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => BroadcastListenerScreen(hostName: roomName),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const NowPlayingScreen(),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Connection failed: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to join room: $e')),
      );
    }
  }

  void _probeAndJoin(String ip, int port, String fallbackName) async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Probing room parameters...';
    });

    try {
      final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 2000);
      final request = await client.getUrl(Uri.parse('http://$ip:$port/info'));
      final response = await request.close();
      if (response.statusCode == HttpStatus.ok) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final name = data['roomName'] ?? fallbackName;
        final typeStr = data['roomType'] ?? 'LOCAL_SYNC';
        final roomType = typeStr == 'LIVE_BROADCAST' ? RoomType.LIVE_BROADCAST : RoomType.LOCAL_SYNC;
        _joinDiscoveredRoom(ip, port, name, roomType: roomType);
      } else {
        _joinDiscoveredRoom(ip, port, fallbackName, roomType: RoomType.LOCAL_SYNC);
      }
    } catch (_) {
      _joinDiscoveredRoom(ip, port, fallbackName, roomType: RoomType.LOCAL_SYNC);
    }
  }

  void _openQrScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Scan Room QR'),
            backgroundColor: CyberTheme.darkBackground,
          ),
          body: MobileScanner(
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  final qrData = barcode.rawValue!;
                  try {
                    // QR data format: "async://<ip>:<port>"
                    if (qrData.startsWith('async://')) {
                      final parts = qrData.replaceFirst('async://', '').split(':');
                      final ip = parts[0];
                      final port = int.parse(parts[1]);
                      Navigator.pop(context); // Close scanner
                      _probeAndJoin(ip, port, 'QR Room ($ip)');
                    }
                  } catch (e) {
                    debugPrint('Invalid QR Code format: $qrData');
                  }
                }
              }
            },
          ),
        ),
      ),
    );
  }

  void _showManualJoinDialog(BuildContext context) {
    final ipController = TextEditingController();
    final portController = TextEditingController(text: '8081');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: CyberTheme.darkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: CyberTheme.electricBlue, width: 1),
          ),
          title: const Text(
            'Connect via IP Address',
            style: TextStyle(color: Colors.white, fontFamily: 'Outfit'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the Host\'s IP address and Port (shown on the Host\'s screen).',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ipController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Host IP (e.g. 192.168.1.100)',
                  hintStyle: TextStyle(color: Colors.white30),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: CyberTheme.electricBlue),
                  ),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: portController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Port (default: 8081)',
                  hintStyle: TextStyle(color: Colors.white30),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: CyberTheme.electricBlue),
                  ),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('CANCEL', style: TextStyle(color: Colors.white38)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('CONNECT', style: TextStyle(color: CyberTheme.electricBlue, fontWeight: FontWeight.bold)),
              onPressed: () {
                final ip = ipController.text.trim();
                final portStr = portController.text.trim();
                if (ip.isNotEmpty) {
                  final port = int.tryParse(portStr) ?? 8081;
                  Navigator.of(context).pop();
                  _probeAndJoin(ip, port, 'Manual Room ($ip)');
                }
              },
            ),
          ],
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final discovery = ref.watch(discoveryServiceProvider);
    final wsService = ref.watch(websocketServiceProvider);

    if (!_isLoading && widget.isHost && widget.roomType == RoomType.LIVE_BROADCAST) {
      return BroadcastHostConsole(localIp: _localIp, port: _port);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isHost ? 'DJ Host Panel' : 'Join Session',
          style: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: CyberTheme.backgroundGradient,
        ),
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: CyberTheme.electricBlue),
                    const SizedBox(height: 20),
                    Text(_statusMessage, style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              )
            : widget.isHost
                ? _buildHostLayout(wsService)
                : _buildClientLayout(discovery),
      ),
    );
  }

  Widget _buildHostLayout(WebSocketService wsService) {
    final roomName = '${ref.read(usernameProvider)} Room';
    final qrData = 'async://$_localIp:$_port';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Room Details Card
          GlassCard(
            borderColor: CyberTheme.neonPink.withOpacity(0.3),
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ROOM ACTIVE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: CyberTheme.neonPink,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        roomName,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Broadcast IP: $_localIp:$_port',
                        style: const TextStyle(fontSize: 13, color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                // QR Button to expand QR code
                IconButton(
                  icon: const Icon(Icons.qr_code, color: CyberTheme.electricBlue, size: 28),
                  onPressed: () => _showQrDialog(context, qrData, roomName),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms),

          const SizedBox(height: 30),

          // Connected Speaker Clients
          const Text(
            'CONNECTED SPEAKERS',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.white38),
          ),
          const SizedBox(height: 12),

          wsService.peers.isEmpty
              ? Container(
                  height: 90,
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.02),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Text(
                    'No users joined. Waiting for speaker devices to join...',
                    style: TextStyle(color: Colors.white30, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: wsService.peers.length,
                  itemBuilder: (context, index) {
                    final peer = wsService.peers[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: CyberTheme.darkCardOverlay,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: CyberTheme.neonGreen.withOpacity(0.15)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: CyberTheme.neonGreen,
                              boxShadow: [
                                BoxShadow(color: CyberTheme.neonGreen, blurRadius: 4),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  peer.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'OS: ${peer.deviceType}  |  Sync latency: ${peer.latencyMs.round()}ms',
                                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ).animate().slideX(begin: 0.1, end: 0, duration: 300.ms);
                  },
                ),

          const SizedBox(height: 35),

          // Music Selector
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'LOCAL MUSIC SCANNER',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.white38),
              ),
              Row(
                children: [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.sort, color: CyberTheme.electricBlue, size: 20),
                    tooltip: 'Sort songs',
                    onSelected: (option) {
                      ref.read(localLibraryProvider.notifier).updateSortOption(option);
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'title', child: Text('Title (A-Z)')),
                      const PopupMenuItem(value: 'artist', child: Text('Artist (A-Z)')),
                      const PopupMenuItem(value: 'date', child: Text('Date Added')),
                    ],
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.sync,
                      color: ref.watch(localLibraryProvider).isScanning ? Colors.white30 : CyberTheme.neonPink,
                      size: 20,
                    ),
                    tooltip: 'Rescan storage',
                    onPressed: ref.watch(localLibraryProvider).isScanning
                        ? null
                        : () => ref.read(localLibraryProvider.notifier).scanLibrary(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Search Bar
          Container(
            height: 44,
            margin: const EdgeInsets.only(bottom: 16),
            child: TextField(
              onChanged: (val) {
                ref.read(localLibraryProvider.notifier).updateSearchQuery(val.trim());
              },
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search songs or artists...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                filled: true,
                fillColor: Colors.white.withOpacity(0.03),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: CyberTheme.electricBlue, width: 1.2),
                ),
              ),
            ),
          ),

          if (ref.watch(localLibraryProvider).isScanning)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: Column(
                  children: [
                    CircularProgressIndicator(strokeWidth: 2, color: CyberTheme.neonPink),
                    SizedBox(height: 12),
                    Text('Scanning /Music and /Download for MP3s...', style: TextStyle(color: Colors.white30, fontSize: 12)),
                  ],
                ),
              ),
            )
          else if (ref.watch(localLibraryProvider).tracks.where((track) {
            final query = ref.watch(localLibraryProvider).searchQuery.toLowerCase();
            return track.title.toLowerCase().contains(query) ||
                   track.artist.toLowerCase().contains(query);
          }).isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              margin: const EdgeInsets.only(bottom: 20),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.01),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  const Icon(Icons.music_off, color: Colors.white30, size: 36),
                  const SizedBox(height: 12),
                  const Text(
                    'No local MP3 files found in /Music or /Download folders.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _pickLocalFile,
                    child: const Text('Use Files App Picker instead', style: TextStyle(color: CyberTheme.electricBlue, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            )
          else ...[
            // Local Tracks List
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: ref.watch(localLibraryProvider).tracks.where((track) {
                final query = ref.watch(localLibraryProvider).searchQuery.toLowerCase();
                return track.title.toLowerCase().contains(query) ||
                       track.artist.toLowerCase().contains(query);
              }).length,
              itemBuilder: (context, index) {
                final track = ref.watch(localLibraryProvider).tracks.where((track) {
                  final query = ref.watch(localLibraryProvider).searchQuery.toLowerCase();
                  return track.title.toLowerCase().contains(query) ||
                         track.artist.toLowerCase().contains(query);
                }).toList()[index];
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: CyberTheme.darkCardOverlay,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: CyberTheme.electricBlue.withOpacity(0.15)),
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: CyberTheme.neonGradient,
                      ),
                      child: const Icon(Icons.music_note, color: Colors.white),
                    ),
                    title: Text(track.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(track.artist, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    trailing: const Icon(Icons.play_arrow, color: CyberTheme.neonPink),
                    onTap: () => _playTrack(track),
                  ),
                );
              },
            ),
          ],

          const SizedBox(height: 20),
          const Text(
            'DEMO SYNTH TRACKS',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.white38),
          ),
          const SizedBox(height: 12),

          // Demo Track Listings
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: demoTracks.where((track) {
              final query = ref.watch(localLibraryProvider).searchQuery.toLowerCase();
              return track.title.toLowerCase().contains(query) ||
                     track.artist.toLowerCase().contains(query);
            }).length,
            itemBuilder: (context, index) {
              final track = demoTracks.where((track) {
                final query = ref.watch(localLibraryProvider).searchQuery.toLowerCase();
                return track.title.toLowerCase().contains(query) ||
                       track.artist.toLowerCase().contains(query);
              }).toList()[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: CyberTheme.neonGradient,
                    ),
                    child: const Icon(Icons.music_note, color: Colors.white),
                  ),
                  title: Text(track.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(track.artist, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: const Icon(Icons.play_arrow, color: CyberTheme.neonPink),
                  onTap: () => _playTrack(track),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildClientLayout(NetworkDiscoveryService discovery) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // QR Scanning Quick Card
          InkWell(
            onTap: _openQrScanner,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: CyberTheme.neonPink.withOpacity(0.3)),
                gradient: LinearGradient(colors: [CyberTheme.neonPink.withOpacity(0.08), Colors.transparent]),
              ),
              child: const Row(
                children: [
                  Icon(Icons.qr_code_scanner, color: CyberTheme.neonPink, size: 36),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SCAN QR TO CONNECT',
                          style: TextStyle(fontWeight: FontWeight.bold, color: CyberTheme.neonPink, fontSize: 11),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Scan the Host\'s QR code to join instantly',
                          style: TextStyle(color: Colors.white60, fontSize: 13),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 400.ms),

          const SizedBox(height: 40),

          // Discovered list header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'NEARBY ROOMS',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.white38),
              ),
              Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.edit, size: 14, color: CyberTheme.electricBlue),
                    label: const Text(
                      'MANUAL IP',
                      style: TextStyle(color: CyberTheme.electricBlue, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _showManualJoinDialog(context),
                  ),
                  const SizedBox(width: 8),
                  if (discovery.isScanning)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: CyberTheme.electricBlue),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          discovery.discoveredRooms.isEmpty
              ? Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.radar, size: 64, color: Colors.white12)
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .scale(begin: const Offset(0.8, 0.8), end: const Offset(1.2, 1.2), duration: 2.seconds),
                        const SizedBox(height: 16),
                        const Text(
                          'Searching for active DJ rooms...',
                          style: TextStyle(color: Colors.white24, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Ensure you are connected to the Host\'s Wi-Fi network.',
                          style: TextStyle(color: Colors.white24, fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : Expanded(
                  child: ListView.builder(
                    itemCount: discovery.discoveredRooms.length,
                    itemBuilder: (context, index) {
                      final room = discovery.discoveredRooms[index];
                      final isBroadcast = room.roomType == RoomType.LIVE_BROADCAST;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: CyberTheme.darkCardOverlay,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: (isBroadcast ? CyberTheme.electricBlue : CyberTheme.neonPink).withOpacity(0.15)
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          leading: Icon(
                            isBroadcast ? Icons.sensors : Icons.volume_up, 
                            color: isBroadcast ? CyberTheme.electricBlue : CyberTheme.neonPink, 
                            size: 30
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  room.name, 
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                                ),
                              ),
                              if (isBroadcast)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'LIVE',
                                    style: TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text('IP: ${room.ip}:${room.port}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          trailing: const Icon(Icons.chevron_right, color: Colors.white30),
                          onTap: () => _joinDiscoveredRoom(room.ip, room.port, room.name, roomType: room.roomType),
                        ),
                      ).animate().slideY(begin: 0.1, end: 0, duration: 300.ms);
                    },
                  ),
                ),
        ],
      ),
    );
  }

  void _showQrDialog(BuildContext context, String qrData, String roomName) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: CyberTheme.darkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: CyberTheme.electricBlue, width: 1.2),
          ),
          title: Text(
            roomName,
            style: const TextStyle(color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Let other speakers scan this QR code to join your room.',
                style: TextStyle(color: Colors.white60, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 200.0,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                qrData,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          actions: [
            Center(
              child: TextButton(
                child: const Text('CLOSE', style: TextStyle(color: CyberTheme.neonPink, fontWeight: FontWeight.bold)),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        );
      },
    );
  }
}
