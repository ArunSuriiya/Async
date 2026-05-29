import 'package:flutter/material.dart';

class CyberTheme {
  // AMOLED Black & Deep Cyberspace Grays
  static const Color darkBackground = Color(0xFF030308);
  static const Color darkCard = Color(0xFF0A0A16);
  static const Color darkCardOverlay = Color(0x1F0A0A16);
  
  // Neon Electric Glow Accent Colors
  static const Color electricBlue = Color(0xFF00F0FF);
  static const Color neonPink = Color(0xFFFF007F);
  static const Color neonPurple = Color(0xFFB5179E);
  static const Color neonGreen = Color(0xFF39FF14);
  static const Color neonYellow = Color(0xFFFFF200);

  // Linear Gradients
  static const LinearGradient neonGradient = LinearGradient(
    colors: [neonPink, electricBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [darkBackground, Color(0xFF0C091E)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Custom Neon BoxShadow
  static BoxShadow glowShadow({required Color color, double blurRadius = 15}) {
    return BoxShadow(
      color: color.withOpacity(0.4),
      blurRadius: blurRadius,
      spreadRadius: 1,
    );
  }

  // Dark Theme Settings
  static ThemeData get themeData {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: electricBlue,
        secondary: neonPink,
        background: darkBackground,
        surface: darkCard,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: Colors.white,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: Colors.white70,
        ),
        labelLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: electricBlue,
        ),
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final Color borderColor;
  final Color backgroundColor;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;

  const GlassCard({
    Key? key,
    required this.child,
    this.borderRadius = 16,
    this.borderColor = const Color(0x3300F0FF), // Soft electric blue border
    this.backgroundColor = const Color(0x1F0A0A16), // Semi-transparent card
    this.width,
    this.height,
    this.padding,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: borderColor.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 2,
          )
        ],
      ),
      child: child,
    );
  }
}
