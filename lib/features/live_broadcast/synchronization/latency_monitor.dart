import 'package:flutter/foundation.dart';

class LatencyMonitor extends ChangeNotifier {
  final List<double> _latencySamples = [];
  double _jitterMs = 0.0;
  double _averageLatencyMs = 0.0;
  int _reconnectionCount = 0;

  double get jitterMs => _jitterMs;
  double get averageLatencyMs => _averageLatencyMs;
  int get reconnectionCount => _reconnectionCount;

  /// Record a new latency measurement to compute stats
  void recordLatency(double latencyMs) {
    if (latencyMs <= 0) return;

    _latencySamples.add(latencyMs);
    if (_latencySamples.length > 50) {
      _latencySamples.removeAt(0); // Sliding window of 50 packets
    }

    // Average latency
    final sum = _latencySamples.reduce((a, b) => a + b);
    _averageLatencyMs = sum / _latencySamples.length;

    // Jitter: mean absolute deviation of successive latency values
    if (_latencySamples.length > 1) {
      double diffSum = 0.0;
      for (int i = 1; i < _latencySamples.length; i++) {
        diffSum += (_latencySamples[i] - _latencySamples[i - 1]).abs();
      }
      _jitterMs = diffSum / (_latencySamples.length - 1);
    }

    notifyListeners();
  }

  /// Increment reconnection event count
  void recordReconnection() {
    _reconnectionCount++;
    notifyListeners();
  }

  /// Reset monitor statistics
  void reset() {
    _latencySamples.clear();
    _jitterMs = 0.0;
    _averageLatencyMs = 0.0;
    _reconnectionCount = 0;
    notifyListeners();
  }
}
