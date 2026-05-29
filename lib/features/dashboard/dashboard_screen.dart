import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/theme.dart';
import '../../core/providers.dart';
import '../../core/utils/network_utils.dart';
import '../room/room_screen.dart';
import '../../core/network/network_discovery_service.dart';
import '../live_broadcast/presentation/create_room_dialog.dart';


final usernameProvider = StateProvider<String>((ref) => 'DJ_Neon_${100 + (DateTime.now().millisecond % 900)}');
final clientIdProvider = Provider<String>((ref) => const Uuid().v4());

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final TextEditingController _usernameController = TextEditingController();
  String _localIp = 'Determining network...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _usernameController.text = ref.read(usernameProvider);
      _lookupLocalIp();
    });
  }

  Future<void> _lookupLocalIp() async {
    final ip = await NetworkUtils.getLocalWifiIp();
    setState(() {
      _localIp = ip == '127.0.0.1' ? '127.0.0.1 (Offline)' : ip;
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final username = ref.watch(usernameProvider);
    final isSimulator = ref.watch(audioPlayerManagerProvider).simulatorEnabled;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: CyberTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ASYNC',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'One Beat. Multiple Devices.',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.5),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(
                        isSimulator ? Icons.science : Icons.science_outlined,
                        color: isSimulator ? CyberTheme.electricBlue : Colors.white60,
                      ),
                      onPressed: () => _showSettingsSheet(context),
                      tooltip: 'Sync Settings & Simulator',
                    ),
                  ],
                ).animate().fadeIn(duration: 500.ms),

                const SizedBox(height: 40),

                // Username Profile Card (Glassmorphism)
                GlassCard(
                  borderColor: CyberTheme.neonPink.withOpacity(0.2),
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: CyberTheme.neonGradient,
                          boxShadow: [CyberTheme.glowShadow(color: CyberTheme.neonPink, blurRadius: 10)],
                        ),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'YOUR DJ ALIAS',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white.withOpacity(0.4),
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              username,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: CyberTheme.electricBlue, size: 20),
                        onPressed: () => _editUsernameDialog(context),
                      ),
                    ],
                  ),
                ).animate().slideY(begin: 0.2, end: 0, duration: 600.ms, curve: Curves.easeOutQuad),

                const SizedBox(height: 40),

                // Host Mode Card
                GestureDetector(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (context) => const CreateRoomDialog(),
                    );
                  },
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 160),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          CyberTheme.neonPink.withOpacity(0.15),
                          CyberTheme.neonPurple.withOpacity(0.05)
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: CyberTheme.neonPink.withOpacity(0.4), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: CyberTheme.neonPink.withOpacity(0.1),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: CyberTheme.neonPink.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'BECOME THE DJ',
                                    style: TextStyle(
                                      color: CyberTheme.neonPink,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Host Room',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Broadcast local music files & sync nearby devices.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.radio,
                            size: 64,
                            color: CyberTheme.neonPink.withOpacity(0.8),
                          ).animate(onPlay: (c) => c.repeat(reverse: true))
                           .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1), duration: 1.5.seconds),
                        ],
                      ),
                    ),
                  ),
                ).animate().slideY(begin: 0.3, end: 0, delay: 100.ms, duration: 600.ms, curve: Curves.easeOutQuad),

                const SizedBox(height: 20),

                // Join Mode Card
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const RoomScreen(isHost: false),
                      ),
                    );
                  },
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 160),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          CyberTheme.electricBlue.withOpacity(0.15),
                          const Color(0xFF001025).withOpacity(0.05)
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: CyberTheme.electricBlue.withOpacity(0.4), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: CyberTheme.electricBlue.withOpacity(0.1),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: CyberTheme.electricBlue.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'CONNECT SPEAKERS',
                                    style: TextStyle(
                                      color: CyberTheme.electricBlue,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Join Room',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Discover nearby rooms & play stream in perfect sync.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.wifi_find,
                            size: 64,
                            color: CyberTheme.electricBlue.withOpacity(0.8),
                          ).animate(onPlay: (c) => c.repeat(reverse: true))
                           .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1), duration: 1.5.seconds),
                        ],
                      ),
                    ),
                  ),
                ).animate().slideY(begin: 0.4, end: 0, delay: 150.ms, duration: 600.ms, curve: Curves.easeOutQuad),

                const SizedBox(height: 40),

                // Network IP info card
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.wifi, color: Colors.white30, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Local IP: $_localIp',
                      style: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.5,
                        color: Colors.white30,
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 500.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _editUsernameDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: CyberTheme.darkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: CyberTheme.neonPink, width: 1),
          ),
          title: const Text(
            'Change DJ Alias',
            style: TextStyle(color: Colors.white, fontFamily: 'Outfit'),
          ),
          content: TextField(
            controller: _usernameController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter new username...',
              hintStyle: const TextStyle(color: Colors.white30),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: CyberTheme.electricBlue),
              ),
            ),
          ),
          actions: [
            TextButton(
              child: const Text('CANCEL', style: TextStyle(color: Colors.white38)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('SAVE', style: TextStyle(color: CyberTheme.electricBlue, fontWeight: FontWeight.bold)),
              onPressed: () {
                if (_usernameController.text.trim().isNotEmpty) {
                  ref.read(usernameProvider.notifier).state = _usernameController.text.trim();
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: CyberTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final playerManager = ref.watch(audioPlayerManagerProvider);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Sync & Diagnostics Settings',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 12),
                  
                  // Simulator Switch
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Virtual Client Simulator',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tests sync with a local simulated peer',
                            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
                          ),
                        ],
                      ),
                      Switch(
                        activeColor: CyberTheme.electricBlue,
                        value: playerManager.simulatorEnabled,
                        onChanged: (val) {
                          playerManager.toggleSimulator(val);
                        },
                      ),
                    ],
                  ),

                  if (playerManager.simulatorEnabled) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Simulated Network Latency: ${playerManager.simLatency.round()} ms',
                      style: const TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                    Slider(
                      value: playerManager.simLatency,
                      min: 10,
                      max: 300,
                      activeColor: CyberTheme.electricBlue,
                      inactiveColor: Colors.white12,
                      onChanged: (val) {
                        playerManager.updateSimulatorSettings(val, playerManager.simOffset);
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Simulated Clock Offset: ${playerManager.simOffset.round()} ms',
                      style: const TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                    Slider(
                      value: playerManager.simOffset,
                      min: 0,
                      max: 500,
                      activeColor: CyberTheme.neonPink,
                      inactiveColor: Colors.white12,
                      onChanged: (val) {
                        playerManager.updateSimulatorSettings(playerManager.simLatency, val);
                      },
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
