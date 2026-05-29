# Async — Multi-Device Audio Synchronizer

Async is a real-time, low-latency audio sharing application built with Flutter. It lets you synchronize audio playback across multiple devices (Android and iOS) using a single master clock and adaptive drift correction.

## Key Features

1. **Local Music Sync (DJ Mode)**: Host and stream local audio files (.mp3) from your library to any connected devices.
2. **Live Audio Broadcast (MediaProjection)**: Capture system audio from other Android apps (such as Spotify, YouTube, or YouTube Music) and broadcast the raw stream to all connected listener devices.
3. **Master Clock Synchronization**: Utilizes NTP-style clock offset calculation and low-latency Jitter Buffers to keep all devices playing in perfect sync.
4. **Adaptive Drift Correction**: Dynamically adjusts player speeds (between 0.98x and 1.02x) on the fly without pitch alteration to keep delay under 50ms.
5. **Physical Volume Sync**: Adjusting the host device's physical volume keys immediately syncs and adjusts playback volume on all connected listener devices.
6. **Cyberpunk Visuals**: Beautiful dark UI featuring custom neon glowing assets, animated rotating vinyl record discs, and glowing soundwave visualizers.

---

## 📱 Android Installation & Downloads

### 📥 Latest Pre-built APKs (v1.0.0)

| Architecture | Download Link | Description | File Size |
| :--- | :--- | :--- | :--- |
| **ARM64-v8a** (Recommended) | [Async_v1.0.0_arm64-v8a.apk](file:///Users/arun/Documents/code/Async/releases/Async_v1.0.0_arm64-v8a.apk) | For modern Android phones (most devices). | **26.9 MB** |
| **ARMEABI-v7a** | [Async_v1.0.0_armeabi-v7a.apk](file:///Users/arun/Documents/code/Async/releases/Async_v1.0.0_armeabi-v7a.apk) | For older 32-bit Android phones. | **23.0 MB** |
| **x86_64** | [Async_v1.0.0_x86_64.apk](file:///Users/arun/Documents/code/Async/releases/Async_v1.0.0_x86_64.apk) | For Android simulators/emulators. | **29.6 MB** |

### 🛠️ Installation Methods

#### Option A: Quick Install via ADB (Command Line)
If your Android device is connected to your computer via USB debugging:
```bash
# For modern phones (ARM64-v8a)
adb install -r releases/Async_v1.0.0_arm64-v8a.apk

# For older 32-bit phones (ARMEABI-v7a)
adb install -r releases/Async_v1.0.0_armeabi-v7a.apk
```

#### Option B: Manual Installation
1. Download the APK corresponding to your device architecture from the links above (ARM64-v8a is recommended for almost all physical phones).
2. Transfer the `.apk` file to your Android device's internal storage.
3. Open any **File Manager** app on your Android device.
4. Locate the `.apk` file, tap it, and follow the on-screen instructions (allow "Install from Unknown Sources" if prompted by your system).

---

## 🍏 iOS Deployment & Installation

Because iOS restricts direct sideloading of third-party application packages (`.ipa` files) without signing certificates:

### 1. Build and Run from Source
To deploy Async to an iOS device or simulator:
1. Ensure you have **macOS** with **Xcode** and **CocoaPods** installed.
2. Navigate to the project root and run:
   ```bash
   flutter pub get
   cd ios && pod install && cd ..
   ```
3. Open Xcode, select the `Runner.xcworkspace` folder (`/ios/Runner.xcworkspace`), and select your development team under **Signing & Capabilities**.
4. Connect your iPhone and run:
   ```bash
   flutter run -d <your-device-id> --debug
   ```

### 2. Required iOS Network Permissions
When launching Async on iOS for the first time, make sure to grant:
- **Local Network Access**: Needed for mDNS discovery to locate the host device.
- **Microphone / Audio Session permissions**: Enables low-latency audio rendering.

---

## 🚀 How to Use

### 📶 Initial Network Setup
To synchronize audio, **all devices must be on the same local Wi-Fi network**.
*   *Tip:* If no external Wi-Fi router is available, turn on **Portable Wi-Fi Hotspot** on the Host device and connect the Client devices directly to it.

---

### 🎵 1. Local Music Sync Mode
Allows you to stream local music files from the Host to connected client speakers.

#### As a DJ Host:
1. Tap **Host Room** on the main dashboard.
2. Select **Local Music Sync** in the dialog.
3. Use the **Local Music Scanner** to scan for MP3 files in your `/Music` or `/Download` directories (or tap **Files App Picker** to select manually).
4. Tap any track to launch the player screen.
5. Control playback using the Play/Pause, Next, and Previous buttons.

#### As a Speaker Client:
1. Tap **Join Room** on the dashboard.
2. The scanner will automatically list nearby rooms. Tap on the desired room to join.
   - *Alternative 1:* Tap the **QR Code icon** on the Host's screen to display a QR code, then tap **Scan QR** on the Client to join instantly.
   - *Alternative 2:* Tap **Manual IP** on the Client and enter the Host's IP address and Port (shown on the Host console).
3. The track will load and begin playing automatically in sync with the Host.

---

### 🎙️ 2. Live Audio Broadcast Mode
Allows you to broadcast system sounds (Spotify, YouTube, games, etc.) from the Host to client speakers.

#### As a DJ Host:
1. Tap **Host Room** on the main dashboard.
2. Select **Live Audio Broadcast** in the dialog.
3. Android will present a system dialog requesting permission to record system audio. Tap **Start Now**.
4. The Host Console will open, showing active capture diagnostics and input levels.
5. Open any third-party app (e.g. Spotify) and start playing music. The level meter on the Host Console will fluctuate, indicating active streaming.

#### As a Listener Client:
1. Tap **Join Room** on the dashboard.
2. Under "Nearby Rooms", tap on the room labeled with a red **LIVE** badge.
3. You will enter the **Live Stream Listener Screen**, featuring a rotating record disc, neon waveform, and real-time buffer latency options.
4. **Buffer Latency Adjuster**: If you experience audio stuttering due to weak Wi-Fi jitter, use the `+` or `-` buttons (or the slider) to increase the **Target Buffer Delay** (adjustable from 30ms up to 200ms).

---

### 🔊 3. Volume Sync
*   **Host Action**: Simply adjust the physical volume buttons on your Host device.
*   **Sync Effect**: The system captures this change and propagates the new volume fraction to all connected client devices in real-time, automatically scaling the speakers' output level to match the DJ.
