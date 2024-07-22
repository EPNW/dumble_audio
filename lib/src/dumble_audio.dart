import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

export 'package:permission_handler/permission_handler.dart';

typedef RecordingCallback = void Function(Uint8List data);

/// Used to record and play raw audio in various [AudioFormat]s.
class DumbleAudio {
  static const MethodChannel _methodChannel =
      MethodChannel('eu.epnw.dumble_audio/audio');
  static const EventChannel _eventChannel =
      EventChannel('eu.epnw.dumble_audio/audio_stream');

  static bool _hasPermission = false;

  /// Requests microphone permissions. Must be the first call to to plugin.
  ///
  /// If the user has not yet granted permissions, a system dialog will be shown.
  ///
  /// Returns the resulting [PermissionStatus] for the microphone.
  static Future<PermissionStatus> requestPermissions() async {
    final PermissionStatus status = await Permission.microphone.status;
    if (status.isGranted) {
      _hasPermission = true;
      return status;
    }
    if (status.isDenied) {
      // Request
      final PermissionStatus requestedStatus =
          await Permission.microphone.request();
      if (requestedStatus.isGranted) {
        _hasPermission = true;
      }
      return requestedStatus;
    }
    return status;
  }

  /// Invoked with audio samples once the engine is started.
  ///
  /// The format is determined by `recordingFormat` in [startEngine].
  static RecordingCallback? recordingCallback;

  /// Starts the audio engine.
  ///
  /// After this call, you can start recording audio using the
  /// [recordingCallback] and [setMicrophone] and start playing
  /// audio with [addTarget], [scheduleBuffer], [removeTarget]
  /// and [setSpeaker].
  ///
  /// The [recordingFormat] defines what kind of samples the
  /// will be [recordingCallback] invoked with.
  ///
  /// The [playingFormat] defines what kind of data you plan to
  /// send to the playback engine when using [scheduleBuffer].
  /// Not that on iOS, the encoding of the playing format must
  /// be [AudioEncoding.pcmFloat], or an [ArgumentError] is thrown.]
  ///
  /// Make sure to call [stopEngine] when done using it, to release
  /// native resrouces.
  ///
  /// If [requestPermissions] was not invoked, or the user declined
  /// microphone access, the method is a no-op and returns `false`.
  /// If the user has granded permissions, the method returns `true`.
  static Future<bool> startEngine({
    AudioFormat recordingFormat = AudioFormat.standard,
    AudioFormat playingFormat = AudioFormat.standard,
  }) async {
    if (!_hasPermission) {
      return false;
    }
    if (Platform.isIOS && playingFormat.encoding != AudioEncoding.pcmFloat) {
      throw ArgumentError(
          'On iOS, the encoding of the playing format must be AudioEncoding.pcmFloat!');
    }
    _eventChannel
        .receiveBroadcastStream()
        .map<Uint8List>((event) => event as Uint8List)
        .listen((event) {
      RecordingCallback? recordingCallback = DumbleAudio.recordingCallback;
      if (recordingCallback != null) {
        recordingCallback(event);
      }
    });
    final Map<String, Object> arguments = {};
    arguments.addAll(recordingFormat._toMap(true));
    arguments.addAll(playingFormat._toMap(false));
    await _methodChannel.invokeMethod('startEngine', arguments);
    return true;
  }

  /// Stops the audio engine and releases native resources.
  ///
  /// If [requestPermissions] was not invoked, or the user declined
  /// microphone access, the method is a no-op and returns `false`.
  /// If the user has granded permissions, the method returns `true`.
  static Future<bool> stopEngine() async {
    if (!_hasPermission) {
      return false;
    }
    await _methodChannel.invokeMethod('stopEngine');
    return true;
  }

  /// Either enables or disables recording through the microphone.
  ///
  /// If its disabled, the [recordingCallback] won't be invoked.
  /// By default, the microphone is disabled.
  ///
  /// If [requestPermissions] was not invoked, or the user declined
  /// microphone access, the method is a no-op and returns `false`.
  /// If the user has granded permissions, the method returns `true`.
  static Future<bool> setMicrophone(bool enabled) async {
    if (!_hasPermission) {
      return false;
    }
    await _methodChannel.invokeMethod('setMicrophone', {'enabled': enabled});
    return true;
  }

  /// Controls on which device the audio streams are played.
  ///
  /// Most phones have multiple devices to put out audio:
  /// On louder device, the "speaker",  or a more private
  /// device, which is usually used when making calls while
  /// holding the phone againes the ear.
  ///
  /// If [requestPermissions] was not invoked, or the user declined
  /// microphone access, the method is a no-op and returns `false`.
  /// If the user has granded permissions, the method returns `true`.
  static Future<bool> setSpeaker(bool enabled) async {
    if (!_hasPermission) {
      return false;
    }
    await _methodChannel.invokeMethod('setSpeaker', {'enabled': enabled});
    return true;
  }

  /// Instructs the engine to allocate a new audio playback target.
  ///
  /// You can then schedule samples for playback at this target using
  /// [scheduleBuffer].
  ///
  /// Once you are done with that target, use [removeTarget] to release
  /// native resources.
  ///
  /// If [requestPermissions] was not invoked, or the user declined
  /// microphone access, the method is a no-op and returns `false`.
  /// If the user has granded permissions, the method returns `true`.
  static Future<bool> addTarget(int targetId) async {
    if (!_hasPermission) {
      return false;
    }
    await _methodChannel.invokeMethod('addTarget', {'targetId': targetId});
    return true;
  }

  /// Removes a playback target.
  ///
  /// If [requestPermissions] was not invoked, or the user declined
  /// microphone access, the method is a no-op and returns `false`.
  /// If the user has granded permissions, the method returns `true`.
  static Future<bool> removeTarget(int targetId) async {
    if (!_hasPermission) {
      return false;
    }
    await _methodChannel.invokeMethod('removeTarget', {'targetId': targetId});
    return true;
  }

  /// Schedules audio samples for playback.
  ///
  /// The bytes in the `buffer` should match the `playbackFromat` used in
  /// [startEngine]. Also, a target with the `targetId` must be created
  /// using [addTarget] before calling this!
  ///
  /// It can be controlled where to play the audio stream using
  /// [setSpeaker].
  ///
  /// If [requestPermissions] was not invoked, or the user declined
  /// microphone access, the method is a no-op and returns `false`.
  /// If the user has granded permissions, the method returns `true`.
  static Future<bool> scheduleBuffer(int targetId, Uint8List buffer) async {
    if (!_hasPermission) {
      return false;
    }
    await _methodChannel.invokeMethod(
        'scheduleBuffer', {'targetId': targetId, 'buffer': buffer});
    return true;
  }
}

/// Describes an audio format with as [AudioEncoding],
/// [AudioChannelCount] and [sampleRate].
class AudioFormat {
  /// The sample encoding of this format.
  final AudioEncoding encoding;

  /// The number of channels of this format.
  final AudioChannelCount channelCount;

  /// The formats audio sample rate in Hz.
  final int sampleRate;

  const AudioFormat(this.sampleRate, this.encoding, this.channelCount)
      : assert(sampleRate > 0);

  /// The default format: 16000Hz sampling rate, 32bit pcm float, 1 channel mono
  static const AudioFormat standard =
      AudioFormat(16000, AudioEncoding.pcmFloat, AudioChannelCount.mono);

  Map<String, Object> _toMap(bool recording) {
    String prefix = recording ? 'recording' : 'playing';
    return {
      '${prefix}SampleRate': sampleRate,
      '${prefix}Encoding': encoding.index,
      '${prefix}ChannelCount': channelCount.index
    };
  }

  /// How many bytes are needed for 1 millisecond of audio using this format.
  int get bytesPerMs =>
      (sampleRate *
          (encoding == AudioEncoding.pcm16Bit ? 2 : 4) *
          (channelCount == AudioChannelCount.stereo ? 2 : 1)) ~/
      1000;

  @override
  String toString() {
    return 'AudioFormat: SampleRate: $sampleRate, Channels: $channelCount, Encoding: $encoding';
  }
}

enum AudioEncoding { pcm16Bit, pcmFloat }

enum AudioChannelCount {
  mono,
  stereo;

  int toInt() {
    switch (this) {
      case AudioChannelCount.mono:
        return 1;
      case AudioChannelCount.stereo:
        return 2;
    }
  }
}
