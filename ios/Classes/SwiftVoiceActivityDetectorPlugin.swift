import Flutter
import UIKit
import AVFoundation
import DownloadingFileAsset
import VoiceActivityDetector

enum PluginError: Error {
  case invalidArgument
  case fileNotAvailable
  case trackNotAvailable

  var flutterError: FlutterError {
    switch self {
    case .invalidArgument:
      return FlutterError(code: "1001",
                          message: NSLocalizedString("Invalid argument.", comment: "SwiftVoiceActivityDetectorPlugin"),
                          details: nil)
    case .fileNotAvailable:
      return FlutterError(code: "4001",
                          message: NSLocalizedString("File is not available.", comment: "SwiftVoiceActivityDetectorPlugin"),
                          details: nil)
    case .trackNotAvailable:
      return FlutterError(code: "4002",
                          message: NSLocalizedString("Audio track is not available.", comment: "SwiftVoiceActivityDetectorPlugin"),
                          details: nil)
    }
  }
}

public class SwiftVoiceActivityDetectorPlugin: NSObject, FlutterPlugin {
  let eventChannel: FlutterEventChannel
  var eventSink: FlutterEventSink?

  var assetHolder: AVPlayer?
  var assetHolderItem: AVPlayerItem?

  init(eventChannel: FlutterEventChannel) {
    self.eventChannel = eventChannel
    super.init()
    eventChannel.setStreamHandler(self)
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(name: "voice_activity_detector", binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(name: "voice_activity_detector/events", binaryMessenger: registrar.messenger())
    let instance = SwiftVoiceActivityDetectorPlugin(eventChannel: eventChannel)
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
  }

  var isRunning = false

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      guard !isRunning else {
        result(false)
        return
      }
      start(call.arguments as? [String: Any], result)
      return
    case "cancel":
      isRunning = false
      result(nil)
      return
    case "isRunning":
      result(isRunning)
      return
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func start(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard
      let arguments = arguments as? [String: Any],
      let filePath = arguments["filePath"] as? String,
      let timeWindow = arguments["timeWindow"] as? Int,
      [10, 20, 30].contains(timeWindow)
      else {
        result(PluginError.invalidArgument.flutterError)
        return
    }

    let expectedFileSize = arguments["expectedFileSize"] as? Int64
    let timeFrom = arguments["timeFrom"] as? TimeInterval
    let timeTo = arguments["timeTo"] as? TimeInterval

    guard let aggressiveness: VoiceActivityDetector.DetectionAggressiveness = {
      let rawValue = arguments["aggressiveness"] as? Int32 ?? VoiceActivityDetector.DetectionAggressiveness.veryAggressive.rawValue
      return VoiceActivityDetector.DetectionAggressiveness(rawValue: rawValue)
    }()
      else {
        result(PluginError.invalidArgument.flutterError)
        return
    }

    let createAssetResult = createAsset(filePath, expectedFileSize)
    guard case let .success(asset) = createAssetResult else {
      if case let .failure(error) = createAssetResult {
        result(error.flutterError)
      }
      return
    }

    let createTrackReaderResult = createTrackReader(asset, timeFrom, timeTo)
    guard case let .success(reader) = createTrackReaderResult else {
      if case let .failure(error) = createTrackReaderResult {
        result(error.flutterError)
      }
      return
    }

    result(true)

    eventSink?(["event": "started",
                "duration": asset.duration.seconds])

    DispatchQueue.global(qos: .utility).async { [weak self] in
      self?.isRunning = true
      defer { self?.isRunning = false }
      self?.startReading(reader, timeWindow, aggressiveness)
    }
  }

  func createAsset(_ filePath: String, _ expectedFileSize: Int64?) -> Result<AVAsset, PluginError> {
    let url = URL(fileURLWithPath: filePath)

    if let expectedFileSize = expectedFileSize {
      do {
        let attr = try FileManager.default.attributesOfItem(atPath: filePath)
        let actualSize = attr[FileAttributeKey.size] as! Int64
        if actualSize < expectedFileSize {
          let asset = DownloadingFileAsset(localFileURL: url, expectedFileSize: expectedFileSize)
          // FIXME this is a workaround to keep holding asset until the downloading completion.
          //       But AVPlayer possibly costs for CPU.
          assetHolderItem = AVPlayerItem(asset: asset)
          assetHolder = AVPlayer(playerItem: assetHolderItem!)
          return .success(asset)
        }
      } catch {
        NSLog("Failed to open file: \(error.localizedDescription)")
        return .failure(.fileNotAvailable)
      }
    }

    let asset = AVAsset(url: url)
    return .success(asset)
  }

  func createTrackReader(_ asset: AVAsset, _ timeFrom: TimeInterval?, _ timeTo: TimeInterval?) -> Result<AudioTrackReader, PluginError> {
    guard let track = asset.tracks.first else {
      return .failure(.trackNotAvailable)
    }

    var timeRange: CMTimeRange?
    if let timeFrom = timeFrom {
      if let timeTo = timeTo {
        guard timeFrom <= timeTo else  {
          return .failure(.invalidArgument)
        }
        timeRange = CMTimeRange(start: CMTime(seconds: timeFrom, preferredTimescale: 1000),
                                end: CMTime(seconds: timeTo, preferredTimescale: 1000))
      } else {
        timeRange = CMTimeRange(start: CMTime(seconds: timeFrom, preferredTimescale: 1000),
                                end: asset.duration)
      }
    } else if let timeTo = timeTo {
      timeRange = CMTimeRange(start: CMTime(seconds: 0, preferredTimescale: 1000),
                              end: CMTime(seconds: timeTo, preferredTimescale: 1000))
    }

    let settings: [String : Any] = [
      AVFormatIDKey: Int(kAudioFormatLinearPCM),
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsNonInterleaved: false,
      AVNumberOfChannelsKey: 1,
      AVSampleRateKey: 8000,
    ]

    do {
      let reader = try AudioTrackReader(track: track, timeRange: timeRange, settings: settings)
      return .success(reader)
    } catch {
      NSLog("Failed to read track: \(error.localizedDescription)")
      return .failure(.trackNotAvailable)
    }
  }

  func startReading(_ reader: AudioTrackReader,
                    _ timeWindow: Int,
                    _ aggressiveness: VoiceActivityDetector.DetectionAggressiveness) {
    let detector = VoiceActivityDetector(agressiveness: aggressiveness)!
    while let sampleBuffer = reader.next() {
      guard let list = detector.detect(sampleBuffer: sampleBuffer, byEachMilliSec: timeWindow) else {
        eventSink?(["event": "finished"])
        return
      }

      if !isRunning {
        eventSink?(["event": "cancelled"])
        return;
      }
      let voiceActivities = list.map { info in
        ["timestamp": info.presentationTimestamp.seconds,
         "voiceActive": info.voiceActivity == .activeVoice]
      }
      eventSink?(["event": "voiceActivities",
                  "voiceActivities": voiceActivities])
    }

    eventSink?(["event": "finished"])
  }
}

extension SwiftVoiceActivityDetectorPlugin: FlutterStreamHandler {
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }
}
