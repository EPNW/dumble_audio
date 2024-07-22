// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

/// Helps to play always the most recent audio.
///
/// In an unstable network environment, data received from a network peer
/// can get delayed and then arrive all at once. If this data are audio
/// samples it might be desirable to drop some samples to have the
/// playback engine always play to the most recent samples.
///
/// Note that on different platfrorms, the native behaviour of the playback engine
/// may differ. On Android for example, all samples scheduled using
/// [DumbleAudio.scheduelBuffer] are played, so you might want use this transformer
/// to drop some before scheduling theme. On iOS on the other hand, only the last
/// schedueled samples are played, so there is theoretically no need for this class.
/// You can however still use it to make the playback behaviour more consistent
/// across multiple platforms.
class FrameDropTransformer extends StreamTransformerBase<Uint8List, Uint8List> {
  /// The time, in milliseconds, how long before the (theoretical) playback end
  /// of the last passed-on samples, new samples are passed on.
  ///
  /// This is needed because usually, the samples need some time after beeing
  /// passed-on to "travel" to the playback hardware. Setting this value to low
  /// will cause the playback engine to have a playback gap while the previous
  /// samples finished playing and the next samples are still traveling. On the
  /// other hand, setting this value to high might cause schedueling samples to
  /// soon and not waiting long enough for the most recent samples from the
  /// network peer.
  ///
  /// In conclustion, a reasonable value for this field seems to be `10`.
  final int aheadTimeMs;

  /// Whether to print debug information to the console.
  ///
  /// Only use this in debug builds to examin, how many frames dropped.
  final bool printStats;

  /// Controlls the `sync` parameter of underlying [StreamController] in [bind].
  final bool syncOutput;

  /// How many bytes are needed for 1 millisecond of audio using this format.
  final int bytesPerMs;

  /// The transformer works by passing through audio samples to the next consumer.
  ///
  /// Using [bytesPerMs] it can know, how long it will take the next consumer to play
  /// all samples on the sound hardware. During this time, the transformer buffers
  /// all incoming audio samples. Then, [aheadTimeMs] before the playback whould end,
  /// it sends the most recently received audio samples to the consumer.
  FrameDropTransformer({
    required this.bytesPerMs,
    this.aheadTimeMs = 10,
    this.syncOutput = false,
    this.printStats = false,
  });

  @override
  Stream<Uint8List> bind(Stream<Uint8List> stream) {
    StreamController<Uint8List>? controller;
    _Helper helper =
        _Helper(bytesPerMs, aheadTimeMs, (Uint8List a) => controller?.add(a));
    StreamSubscription<Uint8List>? sub;
    controller = StreamController(
        sync: syncOutput,
        onCancel: () {
          helper.stop();
          if (printStats) {
            print(helper.toString());
          }
          controller?.close();
          sub?.cancel();
        });
    sub = stream.listen(helper.feed, onDone: () {
      helper.stop();
      if (printStats) {
        print(helper.toString());
      }
      controller?.close();
    });
    return controller.stream;
  }
}

typedef _HelperCallback = void Function(Uint8List a);

class _Helper {
  final Queue<Uint8List> _stack;
  int _nextPlayDoneTime;
  int _nextRescheduleTime;
  bool _stopped;
  final int bytesPerMs;
  final int aheadTimeMs;
  final Stopwatch _watch;
  bool _dirty;
  final _HelperCallback callback;
  int _feedCallbackCount;
  int _checkCallbackCount;
  int _dropInFeedCount;
  int _dropInCheckCount;

  _Helper(this.bytesPerMs, this.aheadTimeMs, this.callback)
      : _stack = Queue<Uint8List>(),
        _nextPlayDoneTime = 0,
        _nextRescheduleTime = 0,
        _stopped = false,
        _watch = Stopwatch(),
        _dirty = false,
        _feedCallbackCount = 0,
        _checkCallbackCount = 0,
        _dropInFeedCount = 0,
        _dropInCheckCount = 0 {
    _watch.start();
  }

  int _now() {
    return _watch.elapsedMilliseconds;
  }

  void feed(Uint8List a) {
    int n = _now();
    if (_nextRescheduleTime <= n) {
      int frameTimeMs = a.lengthInBytes ~/ bytesPerMs;
      if (_nextPlayDoneTime < n) {
        _nextPlayDoneTime = n + frameTimeMs;
      } else {
        _nextPlayDoneTime = _nextPlayDoneTime + frameTimeMs;
      }
      _nextRescheduleTime = _nextPlayDoneTime - aheadTimeMs;
      _dropInFeedCount += _stack.length;
      _stack.clear();
      _feedCallbackCount++;
      callback(a);
    } else {
      _stack.addLast(a);
      if (!_dirty) {
        _dirty = true;
        Timer.run(_check);
      }
    }
  }

  void _check() {
    _dirty = false;
    if (!_stopped) {
      int n = _now();
      if (_nextRescheduleTime <= n) {
        if (_stack.isNotEmpty) {
          Uint8List a = _stack.first;
          _dropInCheckCount += (_stack.length - 1);
          _stack.clear();
          int frameTimeMs = a.lengthInBytes ~/ bytesPerMs;
          if (_nextPlayDoneTime < n) {
            _nextPlayDoneTime = n + frameTimeMs;
          } else {
            _nextPlayDoneTime = _nextPlayDoneTime + frameTimeMs;
          }
          _nextRescheduleTime = _nextPlayDoneTime - aheadTimeMs;
          _checkCallbackCount++;
          callback(a);
        }
      } else {
        if (!_dirty) {
          _dirty = true;
          Timer.run(_check);
        }
      }
    }
  }

  void stop() {
    _stopped = true;
    _watch.stop();
  }

  @override
  String toString() {
    int dropCount = _dropInCheckCount + _dropInFeedCount;
    return '_Helper: Invoked $_feedCallbackCount by feed, $_checkCallbackCount by _check, dropped $dropCount ($_dropInFeedCount in feed, $_dropInCheckCount in _check)';
  }
}
