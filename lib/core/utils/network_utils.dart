import 'dart:io';
import 'package:flutter/foundation.dart';

class NetworkUtils {
  /// Resolves the best local Wi-Fi or LAN IPv4 address.
  /// Prioritizes interfaces like wlan0, en0, ap0, etc.
  static Future<String> getLocalWifiIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );

      // Prioritize Wi-Fi or Hotspot interfaces
      for (var interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (name.contains('wlan') || name.contains('en') || name.contains('ap')) {
          if (interface.addresses.isNotEmpty) {
            return interface.addresses.first.address;
          }
        }
      }

      // Secondary check: avoid known cell data interfaces (rmnet, etc.)
      for (var interface in interfaces) {
        final name = interface.name.toLowerCase();
        if (!name.contains('rmnet') && !name.contains('p2p') && !name.contains('lo')) {
          if (interface.addresses.isNotEmpty) {
            return interface.addresses.first.address;
          }
        }
      }

      // Fallback
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (e) {
      debugPrint('[NetworkUtils] Error lookup local IP: $e');
    }
    return '127.0.0.1';
  }
}
