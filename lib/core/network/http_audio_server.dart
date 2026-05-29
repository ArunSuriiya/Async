import 'dart:io';
import 'package:flutter/foundation.dart';

class HttpAudioServer {
  HttpServer? _server;
  final Map<String, String> _trackMap = {}; // Maps trackId to local file path
  int _port = 0;

  int get port => _port;
  String get address => _server?.address.address ?? '127.0.0.1';
  bool get isRunning => _server != null;

  /// Start the HTTP server on an available local port
  Future<int> start() async {
    if (_server != null) return _port;

    try {
      // Bind to all local interfaces (IPv4)
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _port = _server!.port;
      debugPrint('[HttpAudioServer] Started server on http://$address:$_port');
      
      _server!.listen(
        _handleRequest,
        onError: (e) {
          debugPrint('[HttpAudioServer] Server error: $e');
        },
      );
      
      return _port;
    } catch (e) {
      debugPrint('[HttpAudioServer] Error starting server: $e');
      rethrow;
    }
  }

  /// Stop the HTTP server
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
    _trackMap.clear();
    debugPrint('[HttpAudioServer] Stopped server.');
  }

  /// Register a local audio track to be streamable
  void registerTrack(String trackId, String filePath) {
    _trackMap[trackId] = filePath;
    debugPrint('[HttpAudioServer] Registered track: $trackId -> $filePath');
  }

  /// Retrieve the direct stream URL for a given track ID
  String getStreamUrl(String hostIp, String trackId) {
    return 'http://$hostIp:$_port/stream?id=$trackId';
  }

  /// Handle incoming HTTP request
  void _handleRequest(HttpRequest request) async {
    // Add CORS headers so web simulators or other sandboxed environments can fetch it
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Range, Content-Type');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    if (request.method != 'GET') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    if (request.uri.path == '/stream') {
      final trackId = request.uri.queryParameters['id'];
      if (trackId == null) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('Missing track id parameter');
        await request.response.close();
        return;
      }

      final filePath = _trackMap[trackId];
      if (filePath == null) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Track not found in registry');
        await request.response.close();
        return;
      }

      final file = File(filePath);
      if (!await file.exists()) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Track file not found on disk');
        await request.response.close();
        return;
      }

      final fileSize = await file.length();
      
      // Basic headers
      request.response.headers.add(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.add(HttpHeaders.contentTypeHeader, 'audio/mpeg');

      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      
      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        try {
          // Parse bytes=start-end (e.g. bytes=2000- or bytes=2000-5000)
          final rangeStr = rangeHeader.substring(6);
          final parts = rangeStr.split('-');
          
          int start = int.parse(parts[0]);
          int end = (parts.length > 1 && parts[1].isNotEmpty)
              ? int.parse(parts[1])
              : fileSize - 1;

          if (start >= fileSize || end >= fileSize || start > end) {
            request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
            request.response.headers.add(HttpHeaders.contentRangeHeader, 'bytes */$fileSize');
            await request.response.close();
            return;
          }

          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.add(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/$fileSize',
          );
          request.response.contentLength = end - start + 1;

          // Open file and stream range
          final fileStream = file.openRead(start, end + 1);
          await request.response.addStream(fileStream);
        } catch (e) {
          debugPrint('[HttpAudioServer] Error parsing Range header "$rangeHeader": $e');
          request.response.statusCode = HttpStatus.badRequest;
        }
      } else {
        // Direct stream
        request.response.statusCode = HttpStatus.ok;
        request.response.contentLength = fileSize;
        await request.response.addStream(file.openRead());
      }
      
      await request.response.close();
    } else {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Resource not found');
      await request.response.close();
    }
  }
}
