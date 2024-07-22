import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:dumble_audio/dumble_audio.dart';
import 'package:opus_dart/opus_dart.dart';

import 'streams.dart';

enum OutputType { s16le, f32le, opusPacket }

class AudioSourceWidget extends StatefulWidget {
  final StreamController<Uint8List> recordTo;
  final int frameTimeMs;
  final ValueChanged<OutputType> outputType;
  final OpusSettings opusSettings;
  const AudioSourceWidget(
      {required this.frameTimeMs,
      required this.opusSettings,
      required this.outputType,
      required this.recordTo,
      Key? key})
      : super(key: key);

  @override
  _AudioSourceWidgetState createState() => _AudioSourceWidgetState();
}

class _AudioSourceWidgetState extends State<AudioSourceWidget> {
  bool _file = true;
  @override
  Widget build(BuildContext context) {
    return new Container(
      child: new Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          new Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('Microphone'),
              new Switch(
                  value: _file,
                  onChanged: (bool newValue) => setState(() {
                        _file = newValue;
                        if (_file) {
                          widget.outputType(OutputType.f32le);
                        }
                      })),
              const Text('File')
            ],
          ),
          _file
              ? new _AssetAudioSource(
                  recordTo: widget.recordTo,
                  frameTimeMs: widget.frameTimeMs,
                )
              : new _DumbleAudioSource(
                  recordTo: widget.recordTo,
                  opusOutput: (bool opusOutput) {
                    opusOutput
                        ? widget.outputType(OutputType.opusPacket)
                        : widget.outputType(OutputType.s16le);
                  },
                  settings: widget.opusSettings)
        ],
      ),
    );
  }
}

class _AssetAudioSource extends StatefulWidget {
  final StreamController<Uint8List> recordTo;
  final int frameTimeMs;
  const _AssetAudioSource(
      {required this.frameTimeMs, required this.recordTo, Key? key})
      : super(key: key);

  @override
  __AssetAudioSourceState createState() => __AssetAudioSourceState();
}

class __AssetAudioSourceState extends State<_AssetAudioSource> {
  bool get _playing => _sub != null;
  StreamSubscription<Uint8List>? _sub;

  @override
  Widget build(BuildContext context) {
    return new ElevatedButton(
        onPressed: _onPressed,
        child: _playing ? const Text('Stop') : const Text('Play'));
  }

  void _onPressed() {
    if (_playing) {
      _sub!.cancel();
      _sub = null;
    } else {
      late final StreamSubscription<Uint8List> sub;
      sub = streamSound(frameTimeMs: widget.frameTimeMs)
          .listen(widget.recordTo.add, onDone: () {
        if (_sub == sub) {
          setState(() {
            _sub = null;
          });
        }
      });
      _sub = sub;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

class _DumbleAudioSource extends StatefulWidget {
  final StreamController<Uint8List> recordTo;
  final ValueChanged<bool>? opusOutput;
  final OpusSettings settings;

  const _DumbleAudioSource(
      {required this.recordTo,
      this.opusOutput,
      required this.settings,
      Key? key})
      : super(key: key);

  @override
  __DumbleAudioSourceState createState() => __DumbleAudioSourceState();
}

class __DumbleAudioSourceState extends State<_DumbleAudioSource> {
  bool _loading = false;
  bool _muted = false;
  bool _encodeOpus = true;
  final StreamController<Uint8List> _record =
      new StreamController.broadcast(sync: true);
  StreamSubscription<Uint8List>? _sub;

  @override
  void initState() {
    if (DumbleAudio.recordingCallback != null) {
      throw new StateError('Recording callback was not disposed correctly!');
    }
    DumbleAudio.recordingCallback = _record.add;
    _switchMute();
    _setOpus(_encodeOpus);
    super.initState();
  }

  void _switchMute() async {
    if (!_loading) {
      setState(() {
        _loading = true;
      });
      _muted = !_muted;
      await DumbleAudio.setMicrophone(!_muted);
      setState(() {
        _loading = false;
      });
    }
  }

  StreamTransformer<Uint8List, Uint8List> newOpusEncoder() {
    return new StreamOpusEncoder.bytes(
            frameTime: widget.settings.opusFrameTime,
            floatInput: false,
            sampleRate: widget.settings.opusSampleRate,
            channels: widget.settings.opusChannelCount,
            application: Application.voip)
        .cast<Uint8List, Uint8List>();
  }

  void _setOpus(bool newValue) {
    _encodeOpus = newValue;
    _sub?.cancel();
    if (_encodeOpus) {
      _sub = _record.stream
          .transform(newOpusEncoder())
          .listen(widget.recordTo.add);
    } else {
      _sub = _record.stream.listen(widget.recordTo.add);
    }
    setState(() {});
    ValueChanged<bool>? callback = widget.opusOutput;
    if (callback != null) {
      callback(_encodeOpus);
    }
  }

  @override
  void dispose() {
    DumbleAudio.recordingCallback = null;
    _record.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return new Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        new IconButton(
            onPressed: _loading ? null : _switchMute,
            icon: new Icon(_muted ? Icons.mic_none : Icons.mic)),
        new Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('Encode with opus'),
            new Switch(value: _encodeOpus, onChanged: _setOpus)
          ],
        )
      ],
    );
  }
}

class OpusSettings {
  final int opusSampleRate;
  final int opusChannelCount;
  final FrameTime opusFrameTime;

  const OpusSettings(
      {required this.opusChannelCount,
      required this.opusFrameTime,
      required this.opusSampleRate});
}
