import 'dart:async';
import 'package:flutter/foundation.dart';

class SyncEngine extends ChangeNotifier {
  // Calculated clock offset (HostTime - ClientTime) in milliseconds
  double _clockOffsetMs = 0;
  
  // Estimated network latency in milliseconds
  double _networkLatencyMs = 0;

  // Running diagnostics
  final List<double> _latencyHistory = [];
  final List<double> _offsetHistory = [];
  
  bool _isSynchronized = false;
  
  // Public Getters
  double get clockOffsetMs => _clockOffsetMs;
  double get networkLatencyMs => _networkLatencyMs;
  bool get isSynchronized => _isSynchronized;
  
  // Current estimated global Host clock time in milliseconds
  int get currentHostTime {
    return DateTime.now().millisecondsSinceEpoch + _clockOffsetMs.round();
  }

  // Convert client local time to host time
  int localToHostTime(int localTimeMs) {
    return localTimeMs + _clockOffsetMs.round();
  }

  // Convert host time to client local time
  int hostToLocalTime(int hostTimeMs) {
    return hostTimeMs - _clockOffsetMs.round();
  }

  /// Reset synchronization stats
  void reset() {
    _clockOffsetMs = 0;
    _networkLatencyMs = 0;
    _latencyHistory.clear();
    _offsetHistory.clear();
    _isSynchronized = false;
    notifyListeners();
  }

  /// Process an NTP exchange.
  /// T1: Client sends request
  /// T2: Host receives request
  /// T3: Host sends response
  /// T4: Client receives response
  void calculateNtpOffset({
    required int t1,
    required int t2,
    required int t3,
    required int t4,
  }) {
    // Round-Trip Time
    double rtt = ((t4 - t1) - (t3 - t2)).toDouble();
    if (rtt < 0) rtt = 0; // Guard against negative RTT due to resolution limits

    // One-way latency (assumed symmetric)
    double latency = rtt / 2;

    // Clock offset: HostTime - ClientTime
    double offset = (((t2 - t1) + (t3 - t4)) / 2);

    _latencyHistory.add(latency);
    _offsetHistory.add(offset);

    // Keep history size small (sliding window of last 10 pings)
    if (_latencyHistory.length > 10) {
      _latencyHistory.removeAt(0);
      _offsetHistory.removeAt(0);
    }

    // High Jitter Filtering: We choose the sample with the lowest RTT (minimum latency)
    // as it represents the packet path least delayed by OS scheduling or network queues.
    int bestIndex = 0;
    double minLatency = double.infinity;
    for (int i = 0; i < _latencyHistory.length; i++) {
      if (_latencyHistory[i] < minLatency) {
        minLatency = _latencyHistory[i];
        bestIndex = i;
      }
    }

    _networkLatencyMs = _latencyHistory[bestIndex];
    _clockOffsetMs = _offsetHistory[bestIndex];
    _isSynchronized = true;

    notifyListeners();
  }

  /// Schedule a task to execute at a precise future Host timestamp
  void scheduleTask(int hostTimestampMs, VoidCallback action) {
    final targetLocalTime = hostToLocalTime(hostTimestampMs);
    final delay = targetLocalTime - DateTime.now().millisecondsSinceEpoch;

    if (delay <= 0) {
      // If time has already passed, run immediately
      action();
    } else {
      Timer(Duration(milliseconds: delay), action);
    }
  }

  /// Force manual synchronization offset (primarily for Host, who is the master reference)
  void setAsHost() {
    _clockOffsetMs = 0;
    _networkLatencyMs = 0;
    _isSynchronized = true;
    notifyListeners();
  }
}
