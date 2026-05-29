import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var livePlayer: LiveAudioPlayer?
  private var volumeObservation: NSKeyValueObservation?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    let playerChannel = FlutterMethodChannel(name: "com.async.async_share/audio_player",
                                              binaryMessenger: controller.binaryMessenger)
    
    let player = LiveAudioPlayer()
    self.livePlayer = player
    
    playerChannel.setMethodCallHandler { (call, result) in
        switch call.method {
        case "startPlayer":
            let args = call.arguments as? [String: Any]
            let sampleRate = args?["sampleRate"] as? Double ?? 48000.0
            let channels = args?["channels"] as? UInt32 ?? 1
            player.start(sampleRate: sampleRate, channels: channels)
            result(true)
        case "stopPlayer":
            player.stop()
            result(true)
        case "playPacket":
            if let args = call.arguments as? [String: Any],
               let typedData = args["data"] as? FlutterStandardTypedData {
                player.playPacket(opusPacket: typedData.data)
                result(true)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Audio packet data cannot be null", details: nil))
            }
        case "setPlaybackSpeed":
            if let args = call.arguments as? [String: Any],
               let speed = args["speed"] as? Double {
                player.setPlaybackSpeed(speed: Float(speed))
                result(true)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Speed must be a double", details: nil))
            }
        case "setVolume":
            if let args = call.arguments as? [String: Any],
               let volume = args["volume"] as? Double {
                player.setVolume(volume: Float(volume))
                result(true)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Volume must be a double", details: nil))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    let volumeChannel = FlutterEventChannel(name: "com.async.async_share/system_volume",
                                            binaryMessenger: controller.binaryMessenger)
    let volumeStreamHandler = SystemVolumeStreamHandler()
    volumeChannel.setStreamHandler(volumeStreamHandler)

    let session = AVAudioSession.sharedInstance()
    do {
        try session.setActive(true)
    } catch {
        print("Failed to activate audio session: \(error)")
    }
    let observation = session.observe(\.outputVolume, options: [.new]) { (session, value) in
        let newVolume = value.newValue ?? 1.0
        volumeStreamHandler.sendVolume(volume: Double(newVolume))
    }
    self.volumeObservation = observation

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

class SystemVolumeStreamHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        let currentVolume = AVAudioSession.sharedInstance().outputVolume
        events(Double(currentVolume))
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    func sendVolume(volume: Double) {
        eventSink?(volume)
    }
}
