import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'core/theme/theme.dart';
import 'features/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Background Audio Engine integration
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.async.share.channel.audio',
      androidNotificationChannelName: 'Async Audio Playback',
      androidNotificationOngoing: true,
      androidShowNotificationBadge: true,
    );
  } catch (e) {
    debugPrint('[Main] Failed to initialize background audio service: $e');
  }

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Async',
      debugShowCheckedModeBanner: false,
      theme: CyberTheme.themeData,
      home: const SplashScreen(),
    );
  }
}
