import UIKit
import Flutter
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var audioEngine: AVAudioEngine?
  private var playerNode: AVAudioPlayerNode?
  private var audioFormat8k: AVAudioFormat?
  private var audioFormatNative: AVAudioFormat?
  private var audioConverter: AVAudioConverter?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let audioChannel = FlutterMethodChannel(name: "gladiator/citofono_audio_track",
                                              binaryMessenger: controller.binaryMessenger)

    audioChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      guard let self = self else { return }
      
      switch call.method {
      case "initAudio":
        self.setupAudioSession()
        self.setupAudioEngine()
        result(true)
      case "writeAudio":
        if let args = call.arguments as? [String: Any],
           let typedData = args["data"] as? FlutterStandardTypedData {
          self.playPCMData(typedData.data)
        }
        result(true)
      case "stopAudio":
        self.stopAudioEngine()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    })

    return super.application(application, launchOptions: launchOptions)
  }

  private func setupAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
      try session.setActive(true)
    } catch {
      print("Error AVAudioSession: \(error.localizedDescription)")
    }
  }

  private func setupAudioEngine() {
    audioEngine = AVAudioEngine()
    playerNode = AVAudioPlayerNode()

    guard let engine = audioEngine, let player = playerNode else { return }

    engine.attach(player)

    // Entrada PCM ESP32: 8 kHz, 16 bits Mono
    audioFormat8k = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 8000.0, channels: 1, interleaved: false)
    
    let mainNode = engine.mainMixerNode
    audioFormatNative = mainNode.outputFormat(forBus: 0)

    guard let format8k = audioFormat8k, let formatNative = audioFormatNative else { return }

    engine.connect(player, to: mainNode, format: formatNative)
    audioConverter = AVAudioConverter(from: format8k, to: formatNative)

    do {
      try engine.start()
      player.play()
    } catch {
      print("Error AVAudioEngine: \(error.localizedDescription)")
    }
  }

  private func playPCMData(_ pcmData: Data) {
    guard let player = playerNode,
          let converter = audioConverter,
          let format8k = audioFormat8k,
          let formatNative = audioFormatNative else { return }

    let frameCount = UInt32(pcmData.count / 2)
    guard frameCount > 0, let inputBuffer = AVAudioPCMBuffer(pcmFormat: format8k, frameCapacity: frameCount) else { return }

    inputBuffer.frameLength = frameCount
    pcmData.withUnsafeBytes { rawBufferPointer in
      if let address = rawBufferPointer.baseAddress {
        memcpy(inputBuffer.int16ChannelData?[0], address, pcmData.count)
      }
    }

    let sampleRateRatio = formatNative.sampleRate / format8k.sampleRate
    let capacityNative = UInt32(Double(frameCount) * sampleRateRatio)
    
    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: formatNative, frameCapacity: capacityNative) else { return }

    var error: NSError?
    let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
      outStatus.pointee = .haveData
      return inputBuffer
    }

    converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

    if error == nil && outputBuffer.frameLength > 0 {
      player.scheduleBuffer(outputBuffer, completionHandler: nil)
    }
  }

  private func stopAudioEngine() {
    playerNode?.stop()
    audioEngine?.stop()
  }
}