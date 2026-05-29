import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/theme.dart';
import '../dashboard/dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 3200), () {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const DashboardScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: CyberTheme.backgroundGradient,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Ambient neon background glow particles
            Positioned(
              top: MediaQuery.of(context).size.height * 0.3,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CyberTheme.neonPink.withOpacity(0.08),
                ),
              ).animate(onPlay: (controller) => controller.repeat(reverse: true))
               .scale(begin: const Offset(0.8, 0.8), end: const Offset(1.2, 1.2), duration: 2.seconds)
               .blur(begin: const Offset(80, 80), end: const Offset(120, 120)),
            ),
            
            Positioned(
              bottom: MediaQuery.of(context).size.height * 0.3,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CyberTheme.electricBlue.withOpacity(0.08),
                ),
              ).animate(onPlay: (controller) => controller.repeat(reverse: true))
               .scale(begin: const Offset(1.2, 1.2), end: const Offset(0.8, 0.8), duration: 2.seconds)
               .blur(begin: const Offset(120, 120), end: const Offset(80, 80)),
            ),

            // Logo & Title
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Glassmorphism Logo Ring
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: CyberTheme.electricBlue,
                        width: 2.5,
                      ),
                      boxShadow: [
                        CyberTheme.glowShadow(color: CyberTheme.electricBlue, blurRadius: 20),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        Icons.sync,
                        size: 55,
                        color: CyberTheme.neonPink,
                      ).animate(onPlay: (controller) => controller.repeat())
                       .rotate(duration: 4.seconds),
                    ),
                  ).animate()
                   .scale(duration: 800.ms, curve: Curves.easeOutBack)
                   .slideY(begin: 0.3, end: 0, duration: 800.ms),
                  
                  const SizedBox(height: 30),
                  
                  // App Title
                  ShaderMask(
                    shaderCallback: (bounds) => CyberTheme.neonGradient.createShader(bounds),
                    child: const Text(
                      'ASYNC',
                      style: TextStyle(
                        fontSize: 52,
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8,
                        color: Colors.white,
                      ),
                    ),
                  ).animate()
                   .fadeIn(delay: 500.ms, duration: 800.ms)
                   .shimmer(delay: 1300.ms, duration: 1.5.seconds),

                  const SizedBox(height: 12),

                  // Tagline
                  const Text(
                    '“One Beat. Multiple Devices.”',
                    style: TextStyle(
                      fontSize: 16,
                      fontStyle: FontStyle.italic,
                      letterSpacing: 1.5,
                      color: Colors.white54,
                    ),
                  ).animate()
                   .fadeIn(delay: 1.seconds, duration: 800.ms),
                ],
              ),
            ),
            
            // Bottom Loading Indicator
            Positioned(
              bottom: 60,
              child: SizedBox(
                width: 140,
                child: Column(
                  children: [
                    const ClipRRect(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                      child: LinearProgressIndicator(
                        backgroundColor: Color(0xFF101025),
                        valueColor: AlwaysStoppedAnimation<Color>(CyberTheme.electricBlue),
                        minHeight: 3,
                      ),
                    ).animate().fadeIn(delay: 1200.ms),
                    const SizedBox(height: 8),
                    const Text(
                      'OFFLINE PROTOCOL ACTIVE',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold,
                        color: Colors.white38,
                      ),
                    ).animate().fadeIn(delay: 1400.ms),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
