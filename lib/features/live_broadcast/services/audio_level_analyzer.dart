import 'dart:async';
import 'package:flutter/foundation.dart';

class AudioLevelAnalyzer extends ChangeNotifier {
  double _currentVolume = 0.0;
  double _smoothedVolume = 0.0;
  StreamSubscription<double>? _levelSubscription;

  double get currentVolume => _currentVolume;
  double get smoothedVolume => _smoothedVolume;

  /// Attach listener to stream of raw volume levels
  void startListening(Stream<double> levelStream) {
    stopListening();
    _levelSubscription = levelStream.listen((level) {
      _currentVolume = level;
      // Exponential moving average to smooth transitions
      _smoothedVolume = 0.35 * level + 0.65 * _smoothedVolume;
      notifyListeners();
    });
  }

  /// Stop listening to level updates
  void stopListening() {
    _levelSubscription?.cancel();
    _levelSubscription = null;
    _currentVolume = 0.0;
    _smoothedVolume = 0.0;
    notifyListeners();
  }

  /// Manually push a volume value
  void updateLevel(double level) {
    _currentVolume = level;
    _smoothedVolume = 0.35 * level + 0.65 * _smoothedVolume;
    notifyListeners();
  }
}
