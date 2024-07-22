import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:dumble_audio/dumble_audio.dart' as dumble_audio;

import 'streams.dart';

/// This example demonstrates to usefulness of a [dumble_audio.FrameDropTransformer].
///
/// It features an audio stream you can interrupt via the UI to simulate network traffic
/// jams, then you can siumlate all audio data beeing received at once.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dumble_audio.DumbleAudio.stopEngine();
  dumble_audio.PermissionStatus status =
      await dumble_audio.DumbleAudio.requestPermissions();
  if (!status.isGranted) {
    return;
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FrameDropTransformer Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'FrameDropTransformer Example'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const dumble_audio.AudioEncoding dFormat =
      dumble_audio.AudioEncoding.pcmFloat;
  static const int sampleRate = 16000;
  final dumble_audio.AudioFormat dumbleConfig = const dumble_audio.AudioFormat(
      sampleRate, dFormat, dumble_audio.AudioChannelCount.mono);
  final int frameSizeMs = 40;
  final int aheadTimeMs = 10;

  bool _playing = false;
  bool _loading = true;
  bool _stopping = false;

  bool _useFrameDropper = false;

  InterruptableTransformer<Uint8List>? _interrupt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _initialize();
    });
  }

  @override
  void dispose() {
    _deinitialize();
    super.dispose();
  }

  void _initialize() async {
    setState(() {
      _loading = true;
    });
    await dumble_audio.DumbleAudio.startEngine(playingFormat: dumbleConfig);
    await dumble_audio.DumbleAudio.setSpeaker(true);
    setState(() {
      _loading = false;
    });
  }

  void _deinitialize() async {
    dumble_audio.DumbleAudio.recordingCallback = null;
    await dumble_audio.DumbleAudio.stopEngine();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Container(
        alignment: Alignment.center,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                  onPressed: _canPressPlayButton ? _startOrStop : null,
                  child: Text(_playing ? 'Stop' : 'Play')),
              ElevatedButton(
                  onPressed: _canPressPauseButton ? _pauseOrResume : null,
                  child: Text(
                      (_interrupt?.isPaused ?? false) ? 'Resume' : 'Pause')),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Switch(
                      value: _useFrameDropper,
                      onChanged: (bool newValue) => setState(() {
                            _useFrameDropper = newValue;
                          })),
                  const Text('Use frame dropper')
                ],
              )
            ]),
      ),
    );
  }

  bool get _canPressPlayButton => !_loading && !_stopping;
  bool get _canPressPauseButton => _canPressPlayButton && _interrupt != null;

  void _pauseOrResume() {
    if (_interrupt!.isPaused) {
      setState(() {
        _interrupt!.resume();
      });
    } else {
      setState(() {
        _interrupt!.pause();
      });
    }
  }

  void _startOrStop() {
    if (_playing) {
      if (!_stopping) {
        setState(() {
          _stopping = true;
          _interrupt!.resume();
        });
      }
    } else {
      setState(() {
        _loading = true;
      });
      dumble_audio.DumbleAudio.addTarget(1).then((bool value) async {
        setState(() {
          _loading = false;
          _playing = true;
        });
        Stream<Uint8List> frames = streamSound(frameTimeMs: frameSizeMs);
        _interrupt = InterruptableTransformer<Uint8List>();
        frames = frames.transform(_interrupt!);
        if (_useFrameDropper) {
          frames = frames.transform(
            dumble_audio.FrameDropTransformer(
                bytesPerMs: dumbleConfig.bytesPerMs),
          );
        }
        await for (Uint8List buffer in frames) {
          if (!_stopping) {
            dumble_audio.DumbleAudio.scheduleBuffer(1, buffer);
          } else {
            break;
          }
        }
        _interrupt!.resume();
        _interrupt = null;
        setState(() {
          _loading = true;
          _stopping = false;
        });
        await dumble_audio.DumbleAudio.removeTarget(1);
        setState(() {
          _loading = false;
          _playing = false;
        });
      });
    }
  }
}
