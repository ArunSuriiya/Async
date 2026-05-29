import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/theme.dart';
import '../../../core/providers.dart';
import '../../dashboard/dashboard_screen.dart';
import '../services/providers.dart';

class BroadcastHostConsole extends ConsumerStatefulWidget {
  final String localIp;
  final int port;

  const BroadcastHostConsole({
    Key? key,
    required this.localIp,
    required this.port,
  }) : super(key: key);

  @override
  ConsumerState<BroadcastHostConsole> createState() => _BroadcastHostConsoleState();
}

class _BroadcastHostConsoleState extends ConsumerState<BroadcastHostConsole> {
  @override
  Widget build(BuildContext context) {
    final broadcastService = ref.watch(liveBroadcastServiceProvider);
    final wsService = ref.watch(websocketServiceProvider);
    final username = ref.watch(usernameProvider);

    final roomName = '$username\'s Stream';
    final qrData = 'async://${widget.localIp}:${widget.port}';

    // Calculate duration display
    final durationSecs = broadcastService.broadcastDurationSecs;
    final minutes = (durationSecs / 60).floor().toString().padLeft(2, '0');
    final seconds = (durationSecs % 60).toString().padLeft(2, '0');
    final durationStr = '$minutes:$seconds';

    // Calculate average listener latency
    double avgLatency = 0.0;
    if (wsService.peers.isNotEmpty) {
      final sum = wsService.peers.map((p) => p.latencyMs).reduce((a, b) => a + b);
      avgLatency = sum / wsService.peers.length;
    }

    return WillPopScope(
      onWillPop: () async {
        // Confirm close
        return await _showExitConfirmation(context);
      },
      child: Scaffold(
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
                  // Custom App Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
                        onPressed: () async {
                          if (await _showExitConfirmation(context)) {
                            await broadcastService.stopHostBroadcast();
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                      const Column(
                        children: [
                          Text(
                            'LIVE BROADCAST',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                              color: CyberTheme.electricBlue,
                            ),
                          ),
                          Text(
                            'Host Console',
                            style: TextStyle(fontSize: 11, color: Colors.white30),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.qr_code, color: CyberTheme.electricBlue),
                        onPressed: () => _showQrDialog(context, qrData, roomName),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Room Detail Header Card
                  GlassCard(
                    borderColor: CyberTheme.electricBlue.withOpacity(0.3),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: CyberTheme.electricBlue,
                                boxShadow: [
                                  BoxShadow(
                                    color: CyberTheme.electricBlue,
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  )
                                ],
                              ),
                            ).animate(onPlay: (c) => c.repeat(reverse: true))
                             .fadeIn(duration: 800.ms),
                            const SizedBox(width: 10),
                            const Text(
                              'STREAM ACTIVE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: CyberTheme.electricBlue,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          roomName,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'mDNS Address: ${widget.localIp}:${widget.port}',
                          style: const TextStyle(fontSize: 13, color: Colors.white60),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Audio Level Meter (Visualizer)
                  _buildAudioLevelSection(broadcastService.volumeLevel),

                  const SizedBox(height: 28),

                  // Stats Grid
                  const Text(
                    'BROADCAST DIAGNOSTICS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Colors.white38,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.5,
                    children: [
                      _buildStatCard('Bitrate', '${broadcastService.currentBitrateKbps.toStringAsFixed(1)} kbps', Icons.speed, CyberTheme.electricBlue),
                      _buildStatCard('Duration', durationStr, Icons.timer, CyberTheme.neonPink),
                      _buildStatCard('Listeners', broadcastService.listenerCount == 0 ? 'No users joined' : '${broadcastService.listenerCount} connected', Icons.people_outline, CyberTheme.neonGreen),
                      _buildStatCard('Avg Latency', '${avgLatency.toStringAsFixed(0)} ms', Icons.network_check, CyberTheme.neonPurple),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Connected Listeners List
                  const Text(
                    'CONNECTED SPEAKERS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Colors.white38,
                    ),
                  ),
                  const SizedBox(height: 12),

                  wsService.peers.isEmpty
                      ? Container(
                          height: 100,
                          width: double.infinity,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.01),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.wifi_tethering, color: Colors.white24, size: 28),
                              SizedBox(height: 8),
                              Text(
                                'No users joined. Waiting for listeners to join...',
                                style: TextStyle(color: Colors.white30, fontSize: 12),
                              ),
                            ],
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
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'OS: ${peer.deviceType}  |  Sync delay: ${peer.latencyMs.round()}ms',
                                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                  const SizedBox(height: 48),

                  // Stop Broadcast Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.red.withOpacity(0.4), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.08),
                            blurRadius: 16,
                          )
                        ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.withOpacity(0.05),
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () async {
                          if (await _showExitConfirmation(context)) {
                            await broadcastService.stopHostBroadcast();
                            Navigator.of(context).pop();
                          }
                        },
                        child: const Text(
                          'TERMINATE BROADCAST',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            letterSpacing: 1.2,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAudioLevelSection(double smoothedLevel) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'AUDIO SOURCE INPUT LEVEL',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1.2),
              ),
              Text(
                '${(smoothedLevel * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: CyberTheme.electricBlue),
              ),
            ],
          ),
          const SizedBox(height: 14),
          
          // Audio level meter slider representation
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 20,
              decoration: const BoxDecoration(
                color: Colors.white10,
              ),
              child: Stack(
                children: [
                  FractionallySizedBox(
                    widthFactor: smoothedLevel.clamp(0.0, 1.0),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [CyberTheme.electricBlue, CyberTheme.neonPurple],
                        ),
                      ),
                    ),
                  ),
                  // Meter ticks overlay
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(10, (index) => Container(
                      width: 1,
                      color: Colors.black.withOpacity(0.35),
                    )),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Capturing device system sounds. Play audio in any third party media app (Spotify, YouTube) to stream.',
            style: TextStyle(fontSize: 11, color: Colors.white30, height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.01),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color.withOpacity(0.8)),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.white30, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Outfit'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showExitConfirmation(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CyberTheme.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 1),
        ),
        title: const Text('Stop Broadcast?', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
        content: const Text(
          'This will terminate the system audio capture service and disconnect all speakers.',
          style: TextStyle(color: Colors.white60, fontSize: 13),
        ),
        actions: [
          TextButton(
            child: const Text('CANCEL', style: TextStyle(color: Colors.white38)),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: const Text('STOP', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return result ?? false;
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
