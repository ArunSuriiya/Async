import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'audio_player_manager.dart';

final List<LocalTrack> demoTracks = [
  LocalTrack(
    id: 'synthwave_1',
    title: 'HyperDrive',
    artist: 'Retro Synthwave',
    filePath: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3', // Online fallback
    duration: const Duration(minutes: 6, seconds: 12),
  ),
  LocalTrack(
    id: 'synthwave_2',
    title: 'Neon Dreams',
    artist: 'Cyber Runner',
    filePath: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
    duration: const Duration(minutes: 5, seconds: 2),
  ),
  LocalTrack(
    id: 'ambient_3',
    title: 'Solar Wind',
    artist: 'Deep Space Drone',
    filePath: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-8.mp3',
    duration: const Duration(minutes: 5, seconds: 18),
  ),
];


class LocalLibraryState {
  final List<LocalTrack> tracks;
  final bool isScanning;
  final String sortOption; // 'title', 'artist', 'date'
  final String searchQuery;

  LocalLibraryState({
    this.tracks = const [],
    this.isScanning = false,
    this.sortOption = 'title',
    this.searchQuery = '',
  });

  LocalLibraryState copyWith({
    List<LocalTrack>? tracks,
    bool? isScanning,
    String? sortOption,
    String? searchQuery,
  }) {
    return LocalLibraryState(
      tracks: tracks ?? this.tracks,
      isScanning: isScanning ?? this.isScanning,
      sortOption: sortOption ?? this.sortOption,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class LocalLibraryNotifier extends StateNotifier<LocalLibraryState> {
  LocalLibraryNotifier() : super(LocalLibraryState());

  /// Request permissions and scan for files in background
  Future<void> scanLibrary() async {
    state = state.copyWith(isScanning: true);
    
    try {
      bool hasPermission = false;
      
      if (Platform.isAndroid) {
        // Request appropriate storage permissions depending on Android version
        final statusAudio = await Permission.audio.request();
        if (statusAudio.isGranted) {
          hasPermission = true;
        } else {
          final statusStorage = await Permission.storage.request();
          hasPermission = statusStorage.isGranted;
        }
      } else if (Platform.isIOS) {
        // iOS App Sandbox Documents directory does not require permissions to list
        hasPermission = true;
      }

      if (!hasPermission) {
        debugPrint('[LocalLibrary] Permission denied for local files.');
        state = state.copyWith(isScanning: false, tracks: []);
        return;
      }

      final List<File> audioFiles = [];
      
      if (Platform.isAndroid) {
        // Scan standard Android Music and Download folders
        final directoriesToScan = [
          Directory('/storage/emulated/0/Music'),
          Directory('/storage/emulated/0/Download'),
          Directory('/storage/emulated/0/Audio'),
        ];

        for (var dir in directoriesToScan) {
          if (await dir.exists()) {
            await _scanDirRecursive(dir, audioFiles);
          }
        }
      } else if (Platform.isIOS) {
        final docsDir = await getApplicationDocumentsDirectory();
        await _scanDirRecursive(docsDir, audioFiles);
      }

      // Convert scanned files to LocalTrack objects
      final List<LocalTrack> loadedTracks = [];
      for (var file in audioFiles) {
        final fileName = file.path.split('/').last;
        final nameWithoutExt = fileName.replaceFirst(RegExp(r'\.(mp3|m4a|wav|ogg)$', caseSensitive: false), '');
        
        // Parse "Artist - Title" format if possible, otherwise assign defaults
        String title = nameWithoutExt;
        String artist = 'Local Audio';
        if (nameWithoutExt.contains(' - ')) {
          final parts = nameWithoutExt.split(' - ');
          artist = parts[0].trim();
          title = parts.sublist(1).join(' - ').trim();
        }

        // Try getting actual file metadata or size
        final size = await file.length();
        // Construct track object
        loadedTracks.add(
          LocalTrack(
            id: 'local_${file.path.hashCode}',
            title: title,
            artist: artist,
            filePath: file.path,
            duration: Duration(milliseconds: (size / 24000).round()), // rough estimate if duration metadata not parsed
          ),
        );
      }

      state = state.copyWith(
        tracks: _sortTracks(loadedTracks, state.sortOption),
        isScanning: false,
      );
    } catch (e) {
      debugPrint('[LocalLibrary] Error scanning files: $e');
      state = state.copyWith(isScanning: false);
    }
  }

  Future<void> _scanDirRecursive(Directory dir, List<File> results) async {
    try {
      final List<FileSystemEntity> entities = dir.listSync(recursive: false, followLinks: false);
      for (var entity in entities) {
        if (entity is File) {
          final path = entity.path.toLowerCase();
          if (path.endsWith('.mp3') || path.endsWith('.m4a') || path.endsWith('.wav')) {
            results.add(entity);
          }
        } else if (entity is Directory) {
          // Avoid scanning system or hidden folders
          final dirName = entity.path.split('/').last;
          if (!dirName.startsWith('.') && dirName.toLowerCase() != 'android') {
            await _scanDirRecursive(entity, results);
          }
        }
      }
    } catch (e) {
      // Access denied to a subfolder, ignore and skip
      debugPrint('[LocalLibrary] Skip directory ${dir.path}: $e');
    }
  }

  void updateSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void updateSortOption(String option) {
    state = state.copyWith(
      sortOption: option,
      tracks: _sortTracks(state.tracks, option),
    );
  }

  List<LocalTrack> _sortTracks(List<LocalTrack> list, String option) {
    final sorted = List<LocalTrack>.from(list);
    if (option == 'title') {
      sorted.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    } else if (option == 'artist') {
      sorted.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
    } else if (option == 'date') {
      // Sort by file modified date (newest first)
      sorted.sort((a, b) {
        final fileA = File(a.filePath);
        final fileB = File(b.filePath);
        if (fileA.existsSync() && fileB.existsSync()) {
          return fileB.lastModifiedSync().compareTo(fileA.lastModifiedSync());
        }
        return 0;
      });
    }
    return sorted;
  }
}

// Global provider for local library
final localLibraryProvider = StateNotifierProvider<LocalLibraryNotifier, LocalLibraryState>((ref) {
  final notifier = LocalLibraryNotifier();
  // Automatically start initial scan in background
  notifier.scanLibrary();
  return notifier;
});
