import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

// ignore: non_constant_identifier_names
final VoiceActivityDetector = _VoiceActivityDetector._();

enum VADTimeWindow {
  msec10,
  msec20,
  msec30,
}

int _valueOfTimeWindow(VADTimeWindow timeWindow) {
  switch (timeWindow) {
    case VADTimeWindow.msec10:
      return 10;
    case VADTimeWindow.msec20:
      return 20;
    case VADTimeWindow.msec30:
      return 30;
  }
  return 0;
}

enum VADAggressiveness {
  quality,
  lowBitRate,
  aggressive,
  veryAggressive,
}

int _valueOfVADAggressiveness(VADAggressiveness aggressiveness) {
  switch (aggressiveness) {
    case VADAggressiveness.quality:
      return 0;
    case VADAggressiveness.lowBitRate:
      return 1;
    case VADAggressiveness.aggressive:
      return 2;
    case VADAggressiveness.veryAggressive:
    default:
      return 3;
  }
}

enum VADState {
  idle,
  running,
  finished,
  cancelled,
}

class VoiceActivity {
  final bool isVoiceActive;
  final double timestamp;

  const VoiceActivity(this.isVoiceActive, this.timestamp);
}

class VoiceActivityDetectorValue {
  final VADState state;
  final String sourceFilePath;
  final double duration;

  final VADTimeWindow timeWindow;
  final List<VoiceActivity> voiceActivities;
  final double processedTimestamp;

  VoiceActivityDetectorValue(
    this.state,
    this.sourceFilePath,
    this.duration,
    this.timeWindow,
    this.voiceActivities,
    this.processedTimestamp,
  );

  VoiceActivityDetectorValue copyWith({
    VADState state,
    String sourceFilePath,
    double duration,
    VADTimeWindow timeWindow,
    List<VoiceActivity> voiceActivities,
    double processedTimestamp,
  }) {
    return VoiceActivityDetectorValue(
      state ?? this.state,
      sourceFilePath ?? this.sourceFilePath,
      duration ?? this.duration,
      timeWindow ?? this.timeWindow,
      voiceActivities ?? this.voiceActivities,
      processedTimestamp ?? this.processedTimestamp,
    );
  }

  VoiceActivityDetectorValue added(List<dynamic> activities) {
    // immutable version below, needs more CPU usage.
    // final voiceActivities = this.voiceActivities.sublist(0);

    // mutable version. while there seems no reason to keep immutability, go on with this.
    final voiceActivities = this.voiceActivities;

    var processedTimestamp = this.processedTimestamp;
    activities.forEach((activity) {
      final isVoiceActive = activity['voiceActive'] as bool;
      final timestamp = activity['timestamp'] as double;
      processedTimestamp = timestamp;

      if (voiceActivities.isEmpty || voiceActivities.last.isVoiceActive != isVoiceActive) {
        voiceActivities.add(VoiceActivity(isVoiceActive, timestamp));
      }
    });

    return VoiceActivityDetectorValue(
      state,
      sourceFilePath,
      duration,
      timeWindow,
      voiceActivities,
      processedTimestamp,
    );
  }

  static final empty = VoiceActivityDetectorValue(VADState.idle, null, null, null, [], 0);
}

class _VoiceActivityDetector {
  final _methodChannel = const MethodChannel('voice_activity_detector');
  final _eventChannel = const EventChannel('voice_activity_detector/events');
  final _controller = StreamController<VoiceActivityDetectorValue>.broadcast();

  var _value = VoiceActivityDetectorValue.empty;
  VoiceActivityDetectorValue get value => _value;

  void _setValue(VoiceActivityDetectorValue newValue) {
    if (value == newValue) {
      return;
    }
    _value = newValue;
    _controller.add(newValue);
  }

  Stream<VoiceActivityDetectorValue> get stream => _controller.stream;

  // Prevent to be instantiated.
  _VoiceActivityDetector._() {
    _eventChannel.receiveBroadcastStream().listen(_onEvent, cancelOnError: false);
  }

  Future<bool> start({
    @required String filePath,
    @required VADTimeWindow timeWindow,
    VADAggressiveness aggressiveness = VADAggressiveness.veryAggressive,
    int expectedFileSize,
    double timeFrom,
    double timeTo,
  }) async {
    final Map<dynamic, dynamic> args = {
      "filePath": filePath,
      "timeWindow": _valueOfTimeWindow(timeWindow),
      "aggressiveness": _valueOfVADAggressiveness(aggressiveness),
      "expectedFileSize": expectedFileSize,
      "timeFrom": timeFrom,
      "timeTo": timeTo,
    };

    final installed = await _methodChannel.invokeMethod('start', args);
    if (installed) {
      final newValue = value.copyWith(
        state: VADState.running,
        sourceFilePath: filePath,
        timeWindow: timeWindow,
        voiceActivities: [],
      );
      _setValue(newValue);
    }
    return installed;
  }

  Future<void> cancel() async {
    await _methodChannel.invokeMethod('cancel');
  }

  Future<void> reset() async {
    await _methodChannel.invokeMethod('cancel');
    _setValue(VoiceActivityDetectorValue.empty);
  }

  void _onEvent(event) {
    switch (event['event']) {
      case 'voiceActivities':
        _setValue(value.added(event['voiceActivities']));
        return;
      case 'started':
        print(event['duration']);
        _setValue(value.copyWith(state: VADState.running, duration: event['duration']));
        return;
      case 'finished':
        _setValue(value.copyWith(state: VADState.finished));
        print(value.voiceActivities.length);
        return;
      case 'cancelled':
        if (value.state == VADState.running) {
          _setValue(value.copyWith(state: VADState.cancelled));
        }
        return;
    }
  }
}
