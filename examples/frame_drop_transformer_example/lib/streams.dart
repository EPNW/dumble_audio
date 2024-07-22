// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const String _key = 'assets/sample_f32le_16000_1';

Stream<Uint8List> streamSound(
    {BuildContext? context,
    required int frameTimeMs,
    int bytesPerMs = (4 * 16000) ~/ 1000}) {
  AssetBundle bundle =
      context != null ? DefaultAssetBundle.of(context) : rootBundle;
  int bytesPerFragment = bytesPerMs * frameTimeMs;
  Timer? t;
  StreamController<Uint8List>? controller =
      // ignore: dead_code
      StreamController<Uint8List>(onCancel: t?.cancel);
  bundle.load(_key).then((ByteData byteData) {
    Uint8List value = byteData.buffer
        .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
    List<Uint8List> data = value.fragment(bytesPerFragment).toList();
    if (!controller.isClosed && data.isNotEmpty) {
      controller.add(data[0]);
      if (data.length > 1) {
        int index = 1;
        t = Timer.periodic(Duration(milliseconds: frameTimeMs), (Timer t) {
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

class InterruptableTransformer<A> extends StreamTransformerBase<A, A> {
  Completer<void>? _interrupt;

  void pause() {
    _interrupt ??= Completer<void>();
  }

  void resume() {
    if (!(_interrupt?.isCompleted ?? true)) {
      _interrupt?.complete();
      _interrupt = null;
    }
  }

  bool get isPaused => _interrupt != null;

  @override
  Stream<A> bind(Stream<A> stream) async* {
    await for (A a in stream) {
      Future<void>? interrupt = _interrupt?.future;
      if (interrupt != null) {
        print('Pause');
        await interrupt;
        print('Continue');
      }
      yield a;
    }
  }
}
