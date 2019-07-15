import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:audio/audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:voice_activity_detector/voice_activity_detector.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    _initializer = prepareAudioFile();
  }

  String _audioFilePath;
  Future<void> _initializer;

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> prepareAudioFile() async {
    _audioFilePath = p.join((await getApplicationSupportDirectory()).path, "en_US_35sec.mp3");
    final assetFile = File(_audioFilePath);
    if (await assetFile.exists()) {
      setState(() {});
      return;
    }

    try {
      final data = await rootBundle.load("assets/en_US_35sec.mp3");
      await assetFile.writeAsBytes(data.buffer.asInt8List(), flush: true);
      print("loaded");
    } catch (e) {
      print(e);
      return;
    }

    if (!mounted) return;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
          appBar: AppBar(
            title: const Text('Voice Activity Detector example'),
          ),
          body: FutureBuilder(
              initialData: null,
              future: _initializer,
              builder: (context, _) {
                print("builder");
                if (_audioFilePath == null) {
                  return Container();
                }
                return Center(
                  child: Column(
                    children: <Widget>[
                      StreamBuilder<VoiceActivityDetectorValue>(
                        initialData: VoiceActivityDetector.value,
                        stream: VoiceActivityDetector.stream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Text(snapshot.error.toString());
                          }
                          return Column(
                            children: <Widget>[
                              _invokeButton(snapshot.data.state),
                              Text(snapshot.data.state.toString()),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(90, 8, 40, 0),
                                child: LayoutBuilder(builder: (context, constraints) {
                                  return CustomPaint(
                                    painter: VoiceActivityPainter(snapshot.data),
                                    size: Size(constraints.maxWidth, 8),
                                  );
                                }),
                              ),
                            ],
                          );
                        },
                      ),
                      AudioConsole(_audioFilePath),
                    ],
                  ),
                );
              })),
    );
  }

  Widget _invokeButton(VADState state) {
    final action = (state == VADState.running) ? "Cancel" : "Start";

    return FlatButton(
      onPressed: () {
        if (state == VADState.running) {
          VoiceActivityDetector.cancel();
        } else {
          VoiceActivityDetector.start(
            filePath: _audioFilePath,
            timeWindow: VADTimeWindow.msec10,
            aggressiveness: VADAggressiveness.veryAggressive,
          );
        }
      },
      child: Text(
        "$action Voice Activity Detection",
        style: Theme.of(context).textTheme.button.copyWith(color: Colors.blueAccent),
      ),
    );
  }
}

class AudioConsole extends StatefulWidget {
  final String url;

  AudioConsole(String audioFilePath)
      : url = (audioFilePath != null) ? "file://$audioFilePath".replaceAll(" ", "%20") : null;

  @override
  State<StatefulWidget> createState() {
    return _AudioConsoleState();
  }
}

class _AudioConsoleState extends State<AudioConsole> {
  final _audioPlayer = Audio(single: true);
  double _position = 0;

  @override
  void initState() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() {});
    });
    _audioPlayer.onPlayerPositionChanged.listen((position) {
      setState(() => _position = position);
    });
    _audioPlayer.onPlayerError.listen((error) => print("!!! $error"));

    _audioPlayer.preload(widget.url);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0),
      child: Column(
        children: [
          Row(
            children: [
              _stateIconButton(),
              Expanded(
                child: Slider(
                  max: _audioPlayer.duration.toDouble(),
                  value: _position.toDouble(),
                  onChanged: onDragSeek,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _stateIconButton() {
    switch (_audioPlayer.state) {
      case AudioPlayerState.LOADING:
      case AudioPlayerState.READY:
      case AudioPlayerState.PAUSED:
      case AudioPlayerState.STOPPED:
        return IconButton(icon: Icon(Icons.play_arrow, size: 28.0), onPressed: onTapPlay);
      case AudioPlayerState.PLAYING:
      default:
        return IconButton(icon: Icon(Icons.pause, size: 28.0), onPressed: onTapPause);
    }
  }

  void onTapPause() {
    _audioPlayer.pause();
  }

  void onTapPlay() {
    _audioPlayer.play(widget.url);
  }

  void onDragSeek(double value) {
    _audioPlayer.seek(value);
  }
}

class VoiceActivityPainter extends CustomPainter {
  final VoiceActivityDetectorValue value;

  VoiceActivityPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    if (value.duration == null || value.duration == 0) {
      return;
    }

    for (var i = 0; i < value.voiceActivities.length; i++) {
      final activity = value.voiceActivities[i];
      final next = (i < value.voiceActivities.length - 1) ? value.voiceActivities[i + 1] : null;
      final rect = Rect.fromLTRB(
        activity.timestamp.toDouble() / value.duration * size.width,
        0,
        (next != null)
            ? next.timestamp.toDouble() / value.duration * size.width
            : value.processedTimestamp / value.duration * size.width,
        size.height,
      );

      final color = activity.isVoiceActive ? Colors.red : Colors.blue;
      canvas.drawRect(rect, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return value.voiceActivities.length != (oldDelegate as VoiceActivityPainter).value.voiceActivities.length;
  }
}
