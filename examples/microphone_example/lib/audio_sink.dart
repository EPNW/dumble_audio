import 'dart:async';
import 'dart:typed_data';

import 'package:dumble_audio/dumble_audio.dart';
import 'package:flutter/material.dart';

class AudioSinkWidget extends StatefulWidget {
  final Stream<Uint8List> rawAudio;
  const AudioSinkWidget({required this.rawAudio, Key? key}) : super(key: key);

  @override
  _AudioSinkWidgetState createState() => _AudioSinkWidgetState();
}

class _AudioSinkWidgetState extends State<AudioSinkWidget> {
  bool _playbackEnabled = true;
  bool _speaker = false;
  bool _loading = false;
  StreamSubscription<Uint8List>? _sub;

  @override
  void initState() {
    _init();
    super.initState();
  }

  void _init() async {
    _loading = true;
    await DumbleAudio.addTarget(0);
    _sub = widget.rawAudio.listen((Uint8List buffer) {
      if (_playbackEnabled) {
        DumbleAudio.scheduleBuffer(0, buffer);
      }
    });
    _loading = false;
    _switchSpeaker();
  }

  void _switchPlayback() {
    setState(() {
      _playbackEnabled = !_playbackEnabled;
    });
  }

  void _switchSpeaker() async {
    if (!_loading) {
      setState(() {
        _loading = true;
      });
      _speaker = !_speaker;
      await DumbleAudio.setSpeaker(_speaker);
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return new Container(
      child: new Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          new IconButton(
              onPressed: _loading ? null : _switchPlayback,
              icon:
                  new Icon(_playbackEnabled ? Icons.pause : Icons.play_arrow)),
          new IconButton(
              onPressed: _loading ? null : _switchSpeaker,
              icon: new Icon(
                  _speaker ? Icons.speaker_notes_off : Icons.speaker_notes))
        ],
      ),
    );
  }
}
