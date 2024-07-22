// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dumble/dumble.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;
import 'package:opus_dart/opus_dart.dart' as opus;
import 'package:dumble_audio/dumble_audio.dart';

final ConnectionOptions options = ConnectionOptions(
  host: 'thewire01.pdeg.de',
  port: 64738,
  password: null,
  name: 'DumbleAudioExample_${Random().nextInt(1 << 32)}',
  opus: true,
);

const AudioFormat recordingFormat =
    AudioFormat(16000, AudioEncoding.pcm16Bit, AudioChannelCount.mono);
const AudioFormat playingFormat = AudioFormat.standard;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  opus.initOpus(await opus_flutter.load());
  await DumbleAudio.stopEngine();
  PermissionStatus status = await DumbleAudio.requestPermissions();
  if (!status.isGranted) {
    return;
  }
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  MumbleClient? _mumbleClient;
  AudioFrameSink? _mumbleSink;
  StreamController<List<int>>? _recordingStreamController;

  bool _micEnabled = false;
  bool _speakerEnabled = false;
  bool _loading = true;

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

  void _recordingCallback(Uint8List buffer) {
    _recordingStreamController?.add(buffer);
  }

  void _initialize() async {
    DumbleAudio.recordingCallback = _recordingCallback;
    await DumbleAudio.startEngine(
        playingFormat: playingFormat, recordingFormat: recordingFormat);
    await DumbleAudio.setSpeaker(false);
    _connectToMumble();
  }

  void _deinitialize() async {
    _recordingStreamController?.close();
    DumbleAudio.recordingCallback = null;
    await DumbleAudio.stopEngine();
    await _mumbleClient?.close();
  }

  void _connectToMumble() async {
    try {
      _mumbleClient = await MumbleClient.connect(
          options: options, onBadCertificate: (X509Certificate cert) => true);
      _mumbleClient!.audio.add(MumbleAudioListener());
      setState(() {
        _loading = false;
      });
    } on Exception catch (e) {
      print(e);
    }
  }

  void startRecording() async {
    _mumbleSink = _mumbleClient!.audio.sendAudio(codec: AudioCodec.opus);
    opus.StreamOpusEncoder<int> encoder = opus.StreamOpusEncoder<int>.bytes(
        frameTime: opus.FrameTime.ms10,
        floatInput: false,
        sampleRate: 16000,
        channels: 1,
        application: opus.Application.voip);
    _recordingStreamController = StreamController<List<int>>();
    _recordingStreamController!.stream
        .transform(encoder)
        .map((Uint8List audioBytes) => AudioFrame.outgoing(frame: audioBytes))
        .pipe(_mumbleSink!);
    await DumbleAudio.setMicrophone(true);
    setState(() {
      _micEnabled = true;
    });
  }

  void endRecording() async {
    await DumbleAudio.setMicrophone(false);
    await _recordingStreamController?.close();
    await _mumbleSink?.close();
    _recordingStreamController = null;
    _mumbleSink = null;
    setState(() {
      _micEnabled = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Dumble Example'),
        ),
        body: Center(
          child: Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      IconButton(
                          icon: Icon(
                            _micEnabled ? Icons.mic : Icons.mic_off,
                          ),
                          onPressed: _loading
                              ? null
                              : () async {
                                  if (_micEnabled) {
                                    endRecording();
                                  } else {
                                    startRecording();
                                  }
                                }),
                      IconButton(
                          icon: Icon(
                            _speakerEnabled
                                ? Icons.volume_up
                                : Icons.volume_down,
                          ),
                          onPressed: _loading
                              ? null
                              : () async {
                                  await DumbleAudio.setSpeaker(
                                      !_speakerEnabled);
                                  setState(() {
                                    _speakerEnabled = !_speakerEnabled;
                                  });
                                })
                    ])),
        ),
      ),
    );
  }
}

class MumbleAudioListener with AudioListener {
  final Random _random = Random();
  @override
  void onAudioReceived(Stream<AudioFrame> voiceData, AudioCodec codec,
      User? speaker, TalkMode talkMode) async {
    int session = speaker?.session ?? (1000000 + _random.nextInt(1000000));
    await DumbleAudio.addTarget(session);
    opus.StreamOpusDecoder decoder = opus.StreamOpusDecoder.bytes(
      floatOutput: playingFormat.encoding == AudioEncoding.pcmFloat,
      sampleRate: playingFormat.sampleRate,
      channels: playingFormat.channelCount.toInt(),
    );
    FrameDropTransformer frameDropper =
        FrameDropTransformer(bytesPerMs: playingFormat.bytesPerMs);
    voiceData
        .map((event) => event.frame)
        .where((event) => event.isNotEmpty)
        .cast<Uint8List?>()
        .transform(decoder)
        .cast<Uint8List>()
        .transform(frameDropper)
        .listen((event) {
      DumbleAudio.scheduleBuffer(session, event);
    }, onDone: () async {
      await DumbleAudio.removeTarget(session);
    });
  }
}
