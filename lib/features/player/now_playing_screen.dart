import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/theme.dart';
import '../../core/providers.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/audio/audio_player_manager.dart';
import '../../core/audio/local_music_provider.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> with TickerProviderStateMixin {
  late AnimationController _waveformController;
  late AnimationController _discRotationController;
  bool _showDiagnostics = false;

  @override
  void initState() {
    super.initState();
    _waveformController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _discRotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
  }

  @override
  void dispose() {
    _waveformController.dispose();
    _discRotationController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  void _playNext(WidgetRef ref) {
    final playerManager = ref.read(audioPlayerManagerProvider);
    final current = playerManager.currentTrack;
    if (current == null) return;

    final allTracks = [
      ...ref.read(localLibraryProvider).tracks,
      ...demoTracks,
    ];

    if (allTracks.isEmpty) return;

    final index = allTracks.indexWhere((t) => t.id == current.id);
    if (index == -1) return;

    final nextIndex = (index + 1) % allTracks.length;
    final nextTrack = allTracks[nextIndex];
    playerManager.hostPlay(nextTrack);
  }

  void _playPrevious(WidgetRef ref) {
    final playerManager = ref.read(audioPlayerManagerProvider);
    final current = playerManager.currentTrack;
    if (current == null) return;

    final allTracks = [
      ...ref.read(localLibraryProvider).tracks,
      ...demoTracks,
    ];

    if (allTracks.isEmpty) return;

    final index = allTracks.indexWhere((t) => t.id == current.id);
    if (index == -1) return;

    final prevIndex = (index - 1 + allTracks.length) % allTracks.length;
    final prevTrack = allTracks[prevIndex];
    playerManager.hostPlay(prevTrack);
  }

  void _showPlaylistBottomSheet(BuildContext context, WidgetRef ref) {
    final playerManager = ref.read(audioPlayerManagerProvider);
    final library = ref.watch(localLibraryProvider);
    final allTracks = [...library.tracks, ...demoTracks];

    showModalBottomSheet(
      context: context,
      backgroundColor: CyberTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
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
                    'CHOOSE SONG',
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
              Expanded(
                child: allTracks.isEmpty
                    ? const Center(
                        child: Text(
                          'No tracks available',
                          style: TextStyle(color: Colors.white30),
                        ),
                      )
                    : ListView.builder(
                        itemCount: allTracks.length,
                        itemBuilder: (context, index) {
                          final track = allTracks[index];
                          final isCurrent = playerManager.currentTrack?.id == track.id;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: isCurrent 
                                  ? CyberTheme.electricBlue.withOpacity(0.08) 
                                  : Colors.white.withOpacity(0.01),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isCurrent 
                                    ? CyberTheme.electricBlue.withOpacity(0.4) 
                                    : Colors.white12
                              ),
                            ),
                            child: ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  gradient: isCurrent 
                                      ? CyberTheme.neonGradient 
                                      : LinearGradient(colors: [Colors.white10, Colors.white.withOpacity(0.02)]),
                                ),
                                child: const Icon(Icons.music_note, color: Colors.white),
                              ),
                              title: Text(
                                track.title, 
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isCurrent ? CyberTheme.electricBlue : Colors.white
                                )
                              ),
                              subtitle: Text(
                                track.artist, 
                                style: const TextStyle(color: Colors.white54, fontSize: 12)
                              ),
                              trailing: isCurrent 
                                  ? const Icon(Icons.volume_up, color: CyberTheme.electricBlue)
                                  : const Icon(Icons.play_arrow, color: Colors.white30),
                              onTap: () {
                                Navigator.pop(context); // Close bottom sheet
                                playerManager.hostPlay(track);
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerManager = ref.watch(audioPlayerManagerProvider);
    final wsService = ref.watch(websocketServiceProvider);
    final syncEngine = ref.watch(syncEngineProvider);

    final track = playerManager.currentTrack;
    final isPlaying = playerManager.isPlaying;
    final position = playerManager.position;
    final duration = playerManager.duration;
    
    if (isPlaying) {
      _discRotationController.repeat();
    } else {
      _discRotationController.stop();
    }
    
    final isHost = wsService.isHost;

    // Calculate progress fraction
    final double progress = duration.inMilliseconds > 0 
        ? position.inMilliseconds / duration.inMilliseconds 
        : 0.0;

    return Scaffold(
      body: Stack(
        children: [
          // 1. Dynamic Blurred Background (Album Art Emulator)
          Container(
            decoration: const BoxDecoration(
              color: CyberTheme.darkBackground,
            ),
          ),
          
          // Glowing orb background effects
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: CyberTheme.neonPink.withOpacity(0.12),
              ),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
           .scale(begin: const Offset(1, 1), end: const Offset(1.3, 1.3), duration: 4.seconds),

          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: CyberTheme.electricBlue.withOpacity(0.12),
              ),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
           .scale(begin: const Offset(1.3, 1.3), end: const Offset(1, 1), duration: 4.seconds),

          // Blurred glass overlay
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(color: Colors.transparent),
            ),
          ),

          // 2. Foreground Layout
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // App Bar / Top Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Column(
                        children: [
                          Text(
                            isHost ? 'BROADCASTING' : 'SYNCHRONIZED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                              color: isHost ? CyberTheme.neonPink : CyberTheme.electricBlue,
                            ),
                          ),
                          Text(
                            isHost ? 'DJ Console' : 'Connected Speaker',
                            style: const TextStyle(fontSize: 12, color: Colors.white54),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(
                          _showDiagnostics ? Icons.analytics : Icons.analytics_outlined,
                          color: _showDiagnostics ? CyberTheme.electricBlue : Colors.white60,
                        ),
                        onPressed: () {
                          setState(() {
                            _showDiagnostics = !_showDiagnostics;
                          });
                        },
                      ),
                    ],
                  ),

                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Spinning Disc / Cover Art Art
                        RotationTransition(
                          turns: _discRotationController,
                          child: Container(
                            width: 230,
                            height: 230,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white10, width: 2),
                              boxShadow: [
                                CyberTheme.glowShadow(
                                  color: isPlaying 
                                      ? (isHost ? CyberTheme.neonPink : CyberTheme.electricBlue) 
                                      : Colors.transparent, 
                                  blurRadius: 30
                                ),
                              ],
                              gradient: const SweepGradient(
                                colors: [CyberTheme.darkCard, Color(0xFF15152A), CyberTheme.darkCard],
                                stops: [0.0, 0.5, 1.0],
                              ),
                            ),
                            child: Center(
                              child: Container(
                                width: 210,
                                height: 210,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  image: DecorationImage(
                                    image: NetworkImage(
                                      track?.id.startsWith('synthwave') == true
                                          ? 'https://picsum.photos/id/29/300/300' // Placeholder dynamic images
                                          : 'https://picsum.photos/id/49/300/300'
                                    ),
                                    fit: BoxFit.cover,
                                    colorFilter: ColorFilter.mode(
                                      (isHost ? CyberTheme.neonPink : CyberTheme.electricBlue).withOpacity(0.15),
                                      BlendMode.colorBurn,
                                    ),
                                  ),
                                ),
                                child: Center(
                                  // Center spindle
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: CyberTheme.darkBackground,
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 35),

                        // Track Metadata
                        Text(
                          track?.title ?? 'No Track Loaded',
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ).animate(target: track != null ? 1 : 0).fadeIn(),
                        
                        const SizedBox(height: 6),
                        
                        Text(
                          track?.artist ?? 'Select a track to play',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 3. Custom Waveform Visualizer
                  SizedBox(
                    height: 60,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: WaveformPainter(
                        animationValue: _waveformController.value,
                        isPlaying: isPlaying,
                        color: isHost ? CyberTheme.neonPink : CyberTheme.electricBlue,
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // 4. Progress Slider / Seek Bar
                  Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3.0,
                          activeTrackColor: isHost ? CyberTheme.neonPink : CyberTheme.electricBlue,
                          inactiveTrackColor: Colors.white10,
                          thumbColor: Colors.white,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                        ),
                        child: Slider(
                          value: progress.clamp(0.0, 1.0),
                          onChanged: isHost
                              ? (val) {
                                  final seekPos = (val * duration.inMilliseconds).round();
                                  playerManager.hostSeek(seekPos);
                                }
                              : null, // Clients cannot scrub the track directly
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(position),
                              style: const TextStyle(fontSize: 11, color: Colors.white30),
                            ),
                            Text(
                              _formatDuration(duration),
                              style: const TextStyle(fontSize: 11, color: Colors.white30),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 25),

                  // 5. Neon Playback Controls
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Volume Button placeholder to keep symmetry
                        const SizedBox(width: 48),

                        // Previous Button (Host only)
                        IconButton(
                          icon: Icon(
                            Icons.skip_previous,
                            size: 32,
                            color: isHost ? Colors.white : Colors.white10,
                          ),
                          onPressed: isHost ? () => _playPrevious(ref) : null,
                        ),
                        
                        // Play/Pause Floating Action Circle
                        GestureDetector(
                          onTap: () {
                            if (isHost) {
                              if (isPlaying) {
                                playerManager.hostPause();
                              } else {
                                if (track != null) {
                                  playerManager.hostPlay(track, positionMs: position.inMilliseconds);
                                }
                              }
                            }
                          },
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: CyberTheme.neonGradient,
                              boxShadow: [
                                CyberTheme.glowShadow(
                                  color: isHost ? CyberTheme.neonPink : CyberTheme.electricBlue,
                                  blurRadius: 20
                                ),
                              ],
                            ),
                            child: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              size: 40,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        
                        // Next Button (Host only)
                        IconButton(
                          icon: Icon(
                            Icons.skip_next,
                            size: 32,
                            color: isHost ? Colors.white : Colors.white10,
                          ),
                          onPressed: isHost ? () => _playNext(ref) : null,
                        ),

                        // Playlist/Queue Selector Button (Host only)
                        IconButton(
                          icon: Icon(
                            Icons.playlist_play,
                            size: 28,
                            color: isHost ? Colors.white54 : Colors.white10,
                          ),
                          onPressed: isHost ? () => _showPlaylistBottomSheet(context, ref) : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 6. Sliding Diagnostics Drawer
          if (_showDiagnostics)
            _buildDiagnosticsDrawer(context, playerManager, syncEngine, isHost),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsDrawer(
    BuildContext context, 
    AudioPlayerManager playerManager, 
    SyncEngine syncEngine,
    bool isHost
  ) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      top: MediaQuery.of(context).size.height * 0.40,
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          if (details.delta.dy > 15) {
            setState(() {
              _showDiagnostics = false;
            });
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: CyberTheme.darkCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: CyberTheme.electricBlue.withOpacity(0.3), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: CyberTheme.electricBlue.withOpacity(0.1),
                blurRadius: 30,
                spreadRadius: 2,
              )
            ]
          ),
          child: Column(
            children: [
              // Drag Indicator handle
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'SYNC DIAGNOSTICS',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: Colors.white,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: syncEngine.isSynchronized 
                            ? CyberTheme.neonGreen.withOpacity(0.15) 
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        syncEngine.isSynchronized ? 'SYNCED' : 'UNSYNCED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: syncEngine.isSynchronized ? CyberTheme.neonGreen : Colors.white60,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    _diagnosticRow('NTP Clock Offset', '${syncEngine.clockOffsetMs.toStringAsFixed(1)} ms'),
                    _diagnosticRow('Network Latency (RTT/2)', '${syncEngine.networkLatencyMs.toStringAsFixed(1)} ms'),
                    _diagnosticRow('Role', isHost ? 'Master DJ Host' : 'Speaker client'),
                    
                    if (playerManager.simulatorEnabled) ...[
                      const Divider(color: Colors.white12, height: 24),
                      Row(
                        children: [
                          const Icon(Icons.science, color: CyberTheme.electricBlue, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'VIRTUAL SIMULATOR (DIAGNOSTICS)',
                            style: TextStyle(
                              fontSize: 11, 
                              fontWeight: FontWeight.bold, 
                              color: CyberTheme.electricBlue,
                              letterSpacing: 1.2
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _diagnosticRow('Simulated Drift', '${playerManager.simDriftMs.toStringAsFixed(1)} ms'),
                      _diagnosticRow('Playback Compensation Rate', '${(playerManager.simSpeed * 100).toStringAsFixed(0)}%'),
                      
                      const SizedBox(height: 12),
                      
                      // Progress comparison visualization
                      const Text(
                        'Playhead Real-time Tracking (Host vs Virtual Client):',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      const SizedBox(height: 10),
                      
                      // Host bar
                      _playheadBar(
                        label: 'HOST (MASTER)', 
                        pos: playerManager.position.inMilliseconds, 
                        dur: playerManager.duration.inMilliseconds,
                        color: CyberTheme.neonPink
                      ),
                      const SizedBox(height: 8),
                      // Client bar
                      _playheadBar(
                        label: 'CLIENT (SYNCED)', 
                        pos: playerManager.simPosition.inMilliseconds, 
                        dur: playerManager.duration.inMilliseconds,
                        color: CyberTheme.electricBlue
                      ),
                    ],
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _diagnosticRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _playheadBar({
    required String label, 
    required int pos, 
    required int dur, 
    required Color color
  }) {
    final fraction = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold)),
            Text('${pos}ms', style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        )
      ],
    );
  }


}

// Custom Waveform Painter to draw flowing cyberpunk neon wave bars
class WaveformPainter extends CustomPainter {
  final double animationValue;
  final bool isPlaying;
  final Color color;

  WaveformPainter({
    required this.animationValue,
    required this.isPlaying,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final glowPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final int barCount = 45;
    final double spacing = size.width / barCount;
    final double centerY = size.height / 2;

    for (int i = 0; i < barCount; i++) {
      // Calculate a dynamic height using sine waves
      double heightScale = 0.05;
      if (isPlaying) {
        // High complexity beat simulation
        final wave1 = math.sin((i * 0.3) + (animationValue * math.pi * 2));
        final wave2 = math.cos((i * 0.15) - (animationValue * math.pi * 4));
        heightScale = 0.2 + (wave1.abs() * 0.5) + (wave2.abs() * 0.3);
      } else {
        // Flatline idle wave
        heightScale = 0.05 + 0.04 * math.sin((i * 0.5) + (animationValue * math.pi * 2));
      }

      final double barHeight = size.height * heightScale;
      final double x = i * spacing + (spacing / 2);

      // Draw primary neon bar & glow bar
      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        glowPaint,
      );
      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue || 
           oldDelegate.isPlaying != isPlaying ||
           oldDelegate.color != color;
  }
}
