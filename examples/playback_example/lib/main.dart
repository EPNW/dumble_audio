// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mumble_sounds/mumble_sounds.dart' as mumble_sounds;
import 'package:dumble_audio/dumble_audio.dart' as dumble_audio;

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
      title: 'Playback Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Playback Example'),
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
  static const mumble_sounds.AudioFormat mumbleFormat =
      mumble_sounds.AudioFormat.s16le;
  static const dumble_audio.AudioEncoding dFormat =
      dumble_audio.AudioEncoding.pcm16Bit;
  static const int bytesPerSample = 2;
  static const mumble_sounds.AudioSampleRate mumbleRate =
      mumble_sounds.AudioSampleRate.hz16000;
  static const int sampleRate = 16000;
  final dumble_audio.AudioFormat dumbleConfig = const dumble_audio.AudioFormat(
      sampleRate, dFormat, dumble_audio.AudioChannelCount.mono);

  final int frameSizeMs = 30;

  final mumble_sounds.SoundSample sample =
      mumble_sounds.SoundSample.serverConnected;

  late Duration timePerSample;
  late List<Uint8List> data;
  bool loading = true;
  int playbacks = 0;
  bool playing = false;
  int playNumber = 0;

  @override
  void initState() {
    super.initState();
    sample
        .load(format: mumbleFormat, sampleRate: mumbleRate)
        .then((Uint8List samples) {
      setState(() {
        data = fragment(samples).toList();
        int sampleCount = samples.lengthInBytes ~/ bytesPerSample;
        print('Sample count: $sampleCount');
        int timePerSampleMs = sampleCount ~/ (sampleRate ~/ 1000);
        timePerSample = Duration(milliseconds: timePerSampleMs);
        print('Time per sound: $timePerSample');
        loading = false;
      });
    });
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
    await dumble_audio.DumbleAudio.startEngine(playingFormat: dumbleConfig);
    await dumble_audio.DumbleAudio.setSpeaker(false);
  }

  void _deinitialize() async {
    dumble_audio.DumbleAudio.recordingCallback = null;
    await dumble_audio.DumbleAudio.stopEngine();
    playing = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: loading
            ? const SizedBox(
                width: 30.0,
                height: 30.0,
                child: CircularProgressIndicator(),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Text(
                    'There have been',
                  ),
                  Text(
                    '$playbacks playbacks',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const Text(
                    'in',
                  ),
                  Text(
                    '${timePerSample * playbacks}',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Container(
                    height: 50.0,
                  ),
                  const SpeakerSwitch()
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
          onPressed: loading
              ? null
              : () {
                  if (playing) {
                    setState(() {
                      playing = false;
                    });
                  } else {
                    setState(() {
                      playNumber++;
                      playing = true;
                      startPlaying(playNumber);
                    });
                  }
                },
          tooltip:
              loading ? 'Wait until loaded...' : (playing ? 'Stop' : 'Start'),
          child: Icon(loading
              ? Icons.refresh
              : (playing ? Icons.stop : Icons.play_arrow))),
    );
  }

  Future<void> startPlaying(int myPlayNumber) async {
    await dumble_audio.DumbleAudio.addTarget(myPlayNumber);
    while (playing && myPlayNumber == playNumber) {
      await streamData().forEach((Uint8List frame) async {
        dumble_audio.DumbleAudio.scheduleBuffer(myPlayNumber, frame);
      });
      setState(() {
        playbacks++;
      });
    }
    await dumble_audio.DumbleAudio.removeTarget(myPlayNumber);
  }

  Stream<Uint8List> streamDataPeriodic() {
    return Stream<Uint8List>.periodic(Duration(milliseconds: frameSizeMs),
        (int index) {
      return data[index % data.length];
    }).take(data.length);
  }

  Stream<Uint8List> streamData() => streamDataTimerLoading();

  Stream<Uint8List> streamDataTimerLoading() {
    Duration wait = Duration(milliseconds: frameSizeMs);
    Timer? t;
    StreamController<Uint8List>? controller =
        // ignore: dead_code
        StreamController<Uint8List>(onCancel: t?.cancel);
    sample
        .load(format: mumbleFormat, sampleRate: mumbleRate)
        .then((Uint8List value) {
      List<Uint8List> data = fragment(value).toList();
      if (!controller.isClosed && data.isNotEmpty) {
        controller.add(data[0]);
        if (data.length > 1) {
          int index = 1;
          t = Timer.periodic(wait, (Timer t) {
            if (t.isActive) {
              controller.add(data[index]);
              index++;
              if (index == data.length) {
                t.cancel();
                controller.close();
              }
            }
          });
        }
      }
    });
    return controller.stream;
  }

  Stream<Uint8List> streamDataTimer() {
    Duration wait = Duration(milliseconds: frameSizeMs);
    StreamController<Uint8List>? controller;
    int index = 0;
    Timer t = Timer.periodic(wait, (Timer t) {
      if (t.isActive) {
        controller?.add(data[index]);
        index++;
        if (index == data.length) {
          t.cancel();
          controller?.close();
        }
      }
    });
    controller = StreamController<Uint8List>(onCancel: t.cancel);
    controller.add(data[index]);
    index++;
    return controller.stream;
  }

  Stream<Uint8List> streamDataFuture() async* {
    Duration wait = Duration(milliseconds: frameSizeMs);
    for (int i = 0; i < data.length; i++) {
      yield data[i];
      await Future.delayed(wait);
    }
  }

  List<Uint8List> fragment(Uint8List bytes) {
    int bytesPerFragment = bytesPerSample * (sampleRate * frameSizeMs) ~/ 1000;
    return bytes.fragment(bytesPerFragment).toList();
  }
}

extension _Fragment on Uint8List {
  Iterable<Uint8List> fragment(int bytesPerFragment) sync* {
    int index = 0;
    while (index + bytesPerFragment <= length) {
      yield buffer.asUint8List(offsetInBytes + index, bytesPerFragment);
      index += bytesPerFragment;
    }
    int leftOver = length - index;
    if (leftOver != 0) {
      Uint8List filledUp = Uint8List(bytesPerFragment);
      filledUp.setRange(0, leftOver, this, index);
      yield filledUp;
    }
  }
}

class SpeakerSwitch extends StatefulWidget {
  const SpeakerSwitch({super.key});

  @override
  State<SpeakerSwitch> createState() => _SpeakerSwitchState();
}

class _SpeakerSwitchState extends State<SpeakerSwitch> {
  bool _speaker = false;
  bool _loading = false;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Speaker:'),
        Switch(
            value: _speaker,
            onChanged: _loading
                ? null
                : (bool newState) => setState(() {
                      _speaker = newState;
                      _loading = true;
                      dumble_audio.DumbleAudio.setSpeaker(_speaker)
                          .then((_) => setState(() {
                                _loading = false;
                              }));
                    }))
      ],
    );
  }
}
