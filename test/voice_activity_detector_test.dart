import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_activity_detector/voice_activity_detector.dart';

void main() {
  const channel = const MethodChannel('voice_activity_detector');
  const eventChannel = const EventChannel('voice_activity_detector/event');

  var _running = false;
  Map<String, dynamic> callbackContent;

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'start':
          if (!_running) {
            _running = true;
            return true;
          }

          return false;
        case 'cancel':
          _running = false;
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('sequence', () async {
    expect(VoiceActivityDetector.value.state, VADState.idle);

    expect(
        await VoiceActivityDetector.start(
          filePath: "xyz.mp3",
          timeWindow: VADTimeWindow.msec10,
        ),
        true);

    expect(
        await VoiceActivityDetector.start(
          filePath: "xyz.mp3",
          timeWindow: VADTimeWindow.msec10,
        ),
        false,
        reason: "returns false while the detector already running");

    await VoiceActivityDetector.cancel();
    expect(_running, false);
  });
}
