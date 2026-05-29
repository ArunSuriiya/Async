import 'package:flutter/material.dart';
import '../../../core/theme/theme.dart';
import '../../../core/network/network_discovery_service.dart';
import '../../room/room_screen.dart';

class CreateRoomDialog extends StatefulWidget {
  const CreateRoomDialog({Key? key}) : super(key: key);

  @override
  State<CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<CreateRoomDialog> {
  RoomType _selectedType = RoomType.LOCAL_SYNC;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: CyberTheme.darkCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'HOST NEW ROOM',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Colors.white,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white60),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          const Divider(color: Colors.white12, height: 24),
          const SizedBox(height: 12),

          // Option 1: Local Sync
          _buildOptionCard(
            type: RoomType.LOCAL_SYNC,
            title: 'Local Music Sync',
            description: 'Scan and broadcast local MP3 audio files. Synchronize nearby speaker devices in microsecond phase alignment.',
            icon: Icons.library_music_outlined,
            activeColor: CyberTheme.neonPink,
          ),

          const SizedBox(height: 16),

          // Option 2: Live Broadcast
          _buildOptionCard(
            type: RoomType.LIVE_BROADCAST,
            title: 'Live Audio Broadcast',
            description: 'Capture system output audio in real time (Spotify, YouTube, browsers, games) and broadcast live to connected listeners.',
            icon: Icons.sensors_outlined,
            activeColor: CyberTheme.electricBlue,
          ),

          const SizedBox(height: 32),

          // Confirm Button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: _selectedType == RoomType.LOCAL_SYNC
                      ? [CyberTheme.neonPink, CyberTheme.neonPurple]
                      : [CyberTheme.electricBlue, CyberTheme.neonPurple],
                ),
                boxShadow: [
                  CyberTheme.glowShadow(
                    color: _selectedType == RoomType.LOCAL_SYNC
                        ? CyberTheme.neonPink
                        : CyberTheme.electricBlue,
                    blurRadius: 12,
                  ),
                ],
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context); // Close bottom sheet
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => RoomScreen(
                        isHost: true,
                        roomType: _selectedType,
                      ),
                    ),
                  );
                },
                child: const Text(
                  'CONFIRM & START ROOM',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1.0,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required RoomType type,
    required String title,
    required String description,
    required IconData icon,
    required Color activeColor,
  }) {
    final isSelected = _selectedType == type;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedType = type;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withOpacity(0.06)
              : Colors.white.withOpacity(0.01),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? activeColor : Colors.white10,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? activeColor.withOpacity(0.15) : Colors.white.withOpacity(0.03),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? activeColor : Colors.white38,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      height: 1.4,
                      color: isSelected ? Colors.white70 : Colors.white30,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
