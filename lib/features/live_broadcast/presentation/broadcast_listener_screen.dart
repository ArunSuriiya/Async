import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/theme.dart';
import '../../../core/providers.dart';
import '../services/providers.dart';
import '../services/live_broadcast_service.dart';


class BroadcastListenerScreen extends ConsumerStatefulWidget {
  final String hostName;

  const BroadcastListenerScreen({
    Key? key,
    required this.hostName,
  }) : super(key: key);

  @override
  ConsumerState<BroadcastListenerScreen> createState() => _BroadcastListenerScreenState();
}

class _BroadcastListenerScreenState extends ConsumerState<BroadcastListenerScreen> with TickerProviderStateMixin {
  late AnimationController _waveformController;
  late AnimationController _discRotationController;
  bool _isPlaying = true; // Local playback state flag (Play/Pause)
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
    if (_isPlaying) {
      _discRotationController.repeat();
    }

    // Start playback when entering screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(liveBroadcastServiceProvider).startClientPlayback();
    });
  }

  @override
  void dispose() {
    _waveformController.dispose();
    _discRotationController.dispose();
    // Stop playback on exit
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(liveBroadcastServiceProvider).stopClientPlayback();
    });
    super.dispose();
  }

  void _togglePlayback() async {
    final broadcastService = ref.read(liveBroadcastServiceProvider);
    if (_isPlaying) {
      await broadcastService.stopClientPlayback();
      _discRotationController.stop();
    } else {
      await broadcastService.startClientPlayback();
      _discRotationController.repeat();
    }
    setState(() {
      _isPlaying = !_isPlaying;
    });
  }

  @override
  Widget build(BuildContext context) {
    final broadcastService = ref.watch(liveBroadcastServiceProvider);
    final volume = broadcastService.volumeLevel;

    return Scaffold(
      body: Stack(
        children: [
          // 1. Dark Background
          Container(
            color: CyberTheme.darkBackground,
          ),

          // Glowing neon circle background effects
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: CyberTheme.electricBlue.withOpacity(0.08),
              ),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
           .scale(begin: const Offset(1, 1), end: const Offset(1.2, 1.2), duration: 3.seconds),

          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: CyberTheme.neonPurple.withOpacity(0.08),
              ),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
           .scale(begin: const Offset(1.2, 1.2), end: const Offset(1, 1), duration: 3.seconds),

          // Blurred glass overlay
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(color: Colors.transparent),
            ),
          ),

          // 2. Main Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // App Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Column(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.red,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red,
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    )
                                  ]
                                ),
                              ).animate(onPlay: (c) => c.repeat(reverse: true))
                               .fadeIn(duration: 500.ms),
                              const SizedBox(width: 8),
                              const Text(
                                'LIVE STREAM',
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                  color: Colors.redAccent,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Connected Listener',
                            style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.3)),
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
                        RotationTransition(
                          turns: _discRotationController,
                          child: Container(
                            width: 220,
                            height: 220,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white10, width: 2),
                              boxShadow: [
                                CyberTheme.glowShadow(
                                  color: _isPlaying ? CyberTheme.electricBlue : Colors.transparent,
                                  blurRadius: 20.0 + (volume * 20).round(),
                                ),
                              ],
                              gradient: const SweepGradient(
                                colors: [CyberTheme.darkCard, Color(0xFF101C30), CyberTheme.darkCard],
                                stops: [0.0, 0.5, 1.0],
                              ),
                            ),
                            child: Center(
                              child: Container(
                                width: 200,
                                height: 200,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  image: DecorationImage(
                                    image: const NetworkImage('https://picsum.photos/id/145/300/300'),
                                    fit: BoxFit.cover,
                                    colorFilter: ColorFilter.mode(
                                      CyberTheme.electricBlue.withOpacity(0.15),
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

                        const SizedBox(height: 40),

                        // Host info
                        Text(
                          'Streaming from',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.hostName,
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Opus Audio Codec • 48 kHz Mono',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 3. Audio Waveform Display
                  SizedBox(
                    height: 60,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: BroadcastWaveformPainter(
                        animationValue: _waveformController.value,
                        isPlaying: _isPlaying,
                        volume: volume,
                        color: CyberTheme.electricBlue,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // 4. Quality Specs Grid
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSpecCol('Latency', '${broadcastService.averageLatencyMs.toStringAsFixed(0)} ms'),
                        _buildSpecCol('Jitter', '${broadcastService.jitterMs.toStringAsFixed(1)} ms'),
                        _buildSpecCol('Bitrate', '${broadcastService.currentBitrateKbps.toStringAsFixed(1)} kbps'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 4.5 Target Buffer Delay Slider and Adjustment Buttons
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Target Buffer Delay',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white60,
                              ),
                            ),
                            Text(
                              '${broadcastService.syncEngineClient.targetLatencyMs} ms',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: CyberTheme.electricBlue,
                                fontFamily: 'Outfit',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.white70),
                              onPressed: () {
                                final current = broadcastService.syncEngineClient.targetLatencyMs;
                                final next = (current - 10).clamp(30, 200);
                                broadcastService.syncEngineClient.updateTargetLatency(next);
                              },
                              iconSize: 22,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                                ),
                                child: Slider(
                                  value: broadcastService.syncEngineClient.targetLatencyMs.toDouble(),
                                  min: 30,
                                  max: 200,
                                  divisions: 17, // steps of 10ms (from 30ms to 200ms)
                                  activeColor: CyberTheme.electricBlue,
                                  inactiveColor: Colors.white12,
                                  onChanged: (val) {
                                    broadcastService.syncEngineClient.updateTargetLatency(val.round());
                                  },
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
                              onPressed: () {
                                final current = broadcastService.syncEngineClient.targetLatencyMs;
                                final next = (current + 10).clamp(30, 200);
                                broadcastService.syncEngineClient.updateTargetLatency(next);
                              },
                              iconSize: 22,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 5. Playback Controls
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: Center(
                      child: GestureDetector(
                        onTap: _togglePlayback,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: _isPlaying
                                ? CyberTheme.neonGradient
                                : LinearGradient(colors: [Colors.white10, Colors.white.withOpacity(0.02)]),
                            boxShadow: [
                              CyberTheme.glowShadow(
                                color: _isPlaying ? CyberTheme.electricBlue : Colors.transparent,
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: Icon(
                            _isPlaying ? Icons.volume_up : Icons.volume_off,
                            size: 34,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 6. Sliding Diagnostics Drawer
          if (_showDiagnostics)
            _buildDiagnosticsDrawer(context, broadcastService),
        ],
      ),
    );
  }

  Widget _buildSpecCol(String label, String val) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white30, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(val, style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
      ],
    );
  }

  Widget _buildDiagnosticsDrawer(BuildContext context, LiveBroadcastService service) {
    final syncEngine = service.syncEngineClient;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      top: MediaQuery.of(context).size.height * 0.45,
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
                      'STREAM DIAGNOSTICS',
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
                        color: syncEngine.isRunning
                            ? CyberTheme.neonGreen.withOpacity(0.15)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        syncEngine.isRunning ? 'STREAMING' : 'STOPPED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: syncEngine.isRunning ? CyberTheme.neonGreen : Colors.white60,
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
                    _diagnosticRow('Estimated Latency (Host-to-Player)', '${service.averageLatencyMs.toStringAsFixed(1)} ms'),
                    _diagnosticRow('Packet Network Jitter', '${service.jitterMs.toStringAsFixed(2)} ms'),
                    _diagnosticRow('Clock Synchronization Offset', '${ref.read(syncEngineProvider).clockOffsetMs.toStringAsFixed(1)} ms'),
                    _diagnosticRow('Jitter Buffer Queue Size', '${syncEngine.bufferSize} packets'),
                    _diagnosticRow('Dropped Packets (Buffer Overflow)', '${syncEngine.droppedPackets}'),
                    _diagnosticRow('Adaptive Time Stretch Speed', '${(syncEngine.currentSpeed * 100).toStringAsFixed(0)}%'),
                    const SizedBox(height: 20),
                    
                    // Buffer visual tracking
                    const Text('Jitter Buffer Level (Packets):', style: TextStyle(color: Colors.white38, fontSize: 10)),
                    const SizedBox(height: 8),
                    _bufferIndicatorBar(syncEngine.bufferSize),
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

  Widget _bufferIndicatorBar(int size) {
    // Under 2 is critical low, above 8 is critical high, 3-7 is healthy
    Color barColor = CyberTheme.neonGreen;
    if (size < 2) {
      barColor = Colors.orangeAccent;
    } else if (size > 8) {
      barColor = CyberTheme.neonPink;
    }

    final double fraction = (size / 12).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('0 (Low)', style: TextStyle(color: Colors.white30, fontSize: 9)),
            Text('6 (Healthy)', style: TextStyle(color: Colors.white30, fontSize: 9)),
            Text('12 (High)', style: TextStyle(color: Colors.white30, fontSize: 9)),
          ],
        )
      ],
    );
  }
}

// Waveform Painter mapping to live stream audio volume
class BroadcastWaveformPainter extends CustomPainter {
  final double animationValue;
  final bool isPlaying;
  final double volume;
  final Color color;

  BroadcastWaveformPainter({
    required this.animationValue,
    required this.isPlaying,
    required this.volume,
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

    final int barCount = 40;
    final double spacing = size.width / barCount;
    final double centerY = size.height / 2;

    for (int i = 0; i < barCount; i++) {
      double heightScale = 0.06;
      if (isPlaying) {
        // High complexity system capture visualizer
        final wave = math.sin((i * 0.35) + (animationValue * math.pi * 3));
        // Scale waves based on current active volume RMS
        heightScale = 0.15 + (wave.abs() * 0.5 * (0.2 + volume * 0.8));
      } else {
        heightScale = 0.05 + 0.03 * math.sin((i * 0.4) + (animationValue * math.pi * 2));
      }

      final double barHeight = size.height * heightScale;
      final double x = i * spacing + (spacing / 2);

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
  bool shouldRepaint(covariant BroadcastWaveformPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.volume != volume ||
        oldDelegate.color != color;
  }
}
