import 'dart:async';
import 'dart:typed_data';

import 'audio_sink.dart';
import 'audio_source.dart';
import 'package:flutter/material.dart';
import 'package:dumble_audio/dumble_audio.dart' as dumble_audio;
import 'vad_viz.dart';
import 'energy_transformer.dart';
import 'package:opus_dart/opus_dart.dart' as opus_dart;
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;

const int sampleRate = 16000;
const bool floatRecording = false;
const bool floatPlayback = true;
const int frameTimeMs = 40;
const opus_dart.FrameTime opusFrameTime = opus_dart.FrameTime.ms40;
const int channelCount = 1;
const dumble_audio.AudioFormat playingFormat = dumble_audio.AudioFormat(
    sampleRate,
    floatPlayback
        ? dumble_audio.AudioEncoding.pcmFloat
        : dumble_audio.AudioEncoding.pcm16Bit,
    channelCount == 1
        ? dumble_audio.AudioChannelCount.mono
        : dumble_audio.AudioChannelCount.stereo);
const dumble_audio.AudioFormat recordingFormat = dumble_audio.AudioFormat(
    sampleRate,
    floatRecording
        ? dumble_audio.AudioEncoding.pcmFloat
        : dumble_audio.AudioEncoding.pcm16Bit,
    channelCount == 1
        ? dumble_audio.AudioChannelCount.mono
        : dumble_audio.AudioChannelCount.stereo);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final opusLib = await opus_flutter.load();
  opus_dart.initOpus(opusLib);
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
      title: 'Microphone Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Microphone Example'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final String title;
  const MyHomePage({super.key, required this.title});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _loading = true;

  final Uint8List _empty = Uint8List(0);
  final StreamController<Uint8List> recordTo =
      StreamController<Uint8List>(sync: true);
  final StreamController<double> energy = StreamController<double>(sync: true);
  final GenericFrameAnalyzer analyzer = GenericFrameAnalyzer.f32le();
  late final Stream<Uint8List> play =
      recordTo.stream.transform(analyzer).map((AnalyzedAudio event) {
    energy.add(event.energy);
    return analyzer.inputType != OutputType.s16le ? event.audio : _empty;
  });
  late final VadVizPainter painter = VadVizPainter()
    ..addStream(energy.stream.transform(const Scaler(50.0)));

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
    recordTo.close();
    energy.close();
    super.dispose();
  }

  void _initialize() async {
    setState(() {
      _loading = true;
    });
    await dumble_audio.DumbleAudio.startEngine(
        playingFormat: playingFormat, recordingFormat: recordingFormat);
    setState(() {
      _loading = false;
    });
  }

  void _deinitialize() async {
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
        child: _loading ? const CircularProgressIndicator() : _body(context),
      ),
    );
  }

  void _configureAnalyzer(OutputType newType) {
    if (analyzer.inputType != newType) {
      switch (newType) {
        case OutputType.s16le:
          analyzer.configureS16le();
          break;
        case OutputType.f32le:
          analyzer.configureF32le();
          break;
        case OutputType.opusPacket:
          analyzer.configureOpus(false, sampleRate, channelCount);
          break;
      }
    }
  }

  Widget _body(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AudioSourceWidget(
              frameTimeMs: frameTimeMs,
              recordTo: recordTo,
              outputType: _configureAnalyzer,
              opusSettings: const OpusSettings(
                  opusChannelCount: channelCount,
                  opusFrameTime: opusFrameTime,
                  opusSampleRate: sampleRate),
            ),
            VadViz(painter: painter),
            AudioSinkWidget(rawAudio: play)
          ],
        )
      ],
    );
  }
}
