import 'dart:async';
import 'dart:math';

import 'dart:typed_data';
import 'audio_source.dart';

import 'package:opus_dart/opus_dart.dart';

const double _max = 32767.0;
const double _min = -32768.0;

class AnalyzedAudio {
  final Uint8List audio;
  final double energy;
  const AnalyzedAudio(this.audio, this.energy);
}

class Int16FrameAnalyzer
    extends StreamTransformerBase<Uint8List, AnalyzedAudio> {
  @override
  Stream<AnalyzedAudio> bind(Stream<Uint8List> stream) async* {
    await for (Uint8List bytes in stream) {
      yield new AnalyzedAudio(bytes, Int16FrameEnergy.calculate(bytes));
    }
  }
}

class Int16FrameEnergy extends StreamTransformerBase<Uint8List, double> {
  static double calculate(Uint8List bytes) {
    double energy = 0;
    ByteData data =
        bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes);
    int index = 0;
    while (index + 1 <= data.lengthInBytes) {
      int i = data.getInt16(index, Endian.little);
      double norm = i > 0 ? i / _max : i / _min;
      energy += (norm * norm);
      index += 2;
    }
    return sqrt(energy / (2 * index));
  }

  @override
  Stream<double> bind(Stream<Uint8List> stream) async* {
    await for (Uint8List bytes in stream) {
      yield calculate(bytes);
    }
  }
}

class GenericFrameAnalyzer
    extends StreamTransformerBase<Uint8List, AnalyzedAudio> {
  late OutputType _inputType;
  OutputType get inputType => _inputType;

  BufferedOpusDecoder? _decoder;

  late bool _passthroughPacket;

  GenericFrameAnalyzer._();
  factory GenericFrameAnalyzer.opus(
      bool passthroughPacket, int analyzeSampleRate, int analyzeChannels) {
    return new GenericFrameAnalyzer._()
      ..configureOpus(passthroughPacket, analyzeSampleRate, analyzeChannels);
  }
  factory GenericFrameAnalyzer.s16le() {
    return new GenericFrameAnalyzer._()..configureS16le();
  }
  factory GenericFrameAnalyzer.f32le() {
    return new GenericFrameAnalyzer._()..configureF32le();
  }

  void configureOpus(
      bool passthroughPacket, int analyzeSampleRate, int analyzeChannels) {
    _decoder?.destroy();
    _decoder = new BufferedOpusDecoder(
        sampleRate: analyzeSampleRate,
        channels: analyzeChannels,
        maxOutputBufferSizeBytes:
            _maxSamplesPerPacket(analyzeSampleRate, analyzeChannels) * 4);
    _passthroughPacket = passthroughPacket;
    _inputType = OutputType.opusPacket;
  }

  void configureF32le() {
    _decoder?.destroy();
    _decoder = null;
    _inputType = OutputType.f32le;
  }

  void configureS16le() {
    _decoder?.destroy();
    _decoder = null;
    _inputType = OutputType.s16le;
  }

  @override
  Stream<AnalyzedAudio> bind(Stream<Uint8List> stream) async* {
    await for (Uint8List bytes in stream) {
      if (inputType == OutputType.opusPacket) {
        yield OpusEnergyAnalyzer.calculate(
            bytes, _decoder!, _passthroughPacket);
      } else {
        yield new AnalyzedAudio(
            bytes,
            inputType == OutputType.f32le
                ? Float32FrameEnergy.calculate(bytes)
                : Int16FrameEnergy.calculate(bytes));
      }
    }
  }
}

class Float32FrameAnalyzer
    extends StreamTransformerBase<Uint8List, AnalyzedAudio> {
  @override
  Stream<AnalyzedAudio> bind(Stream<Uint8List> stream) async* {
    await for (Uint8List bytes in stream) {
      yield new AnalyzedAudio(bytes, Float32FrameEnergy.calculate(bytes));
    }
  }
}

class Float32FrameEnergy extends StreamTransformerBase<Uint8List, double> {
  static double calculate(Uint8List bytes) {
    double energy = 0;
    ByteData data =
        bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes);
    int index = 0;
    while (index + 3 <= data.lengthInBytes) {
      double norm = data.getFloat32(index, Endian.little);
      energy += (norm * norm);
      index += 4;
    }
    return sqrt((energy / (4 * index)));
  }

  @override
  Stream<double> bind(Stream<Uint8List> stream) async* {
    await for (Uint8List bytes in stream) {
      yield calculate(bytes);
    }
  }
}

class Scaler extends StreamTransformerBase<double, double> {
  final double scale;

  const Scaler(this.scale);

  @override
  Stream<double> bind(Stream<double> stream) async* {
    await for (double d in stream) {
      yield min(1.0, d * scale);
    }
  }
}

class Normalizer extends StreamTransformerBase<double, double> {
  @override
  Stream<double> bind(Stream<double> stream) async* {
    double max = 0.0;
    await for (double value in stream) {
      if (value == 0.0) {
        yield 0.0;
      } else if (max < value) {
        max = value;
        yield 1.0;
      } else {
        yield value / max;
      }
    }
  }
}

class OpusEnergyAnalyzer
    extends StreamTransformerBase<Uint8List, AnalyzedAudio> {
  final bool passthroughPacket;
  final int analyzeSampleRate;
  final int analyzeChannels;
  const OpusEnergyAnalyzer(
      {required this.passthroughPacket,
      required this.analyzeSampleRate,
      required this.analyzeChannels});

  static AnalyzedAudio calculate(Uint8List opusPacket,
      BufferedOpusDecoder decoder, bool passthroughPacket) {
    decoder.inputBuffer.setAll(0, opusPacket);
    decoder.inputBufferIndex = opusPacket.length - 1;
    decoder.decodeFloat(autoSoftClip: true);
    double energy;
    Uint8List data;
    if (passthroughPacket) {
      data = opusPacket;
      energy = Float32FrameEnergy.calculate(decoder.outputBuffer);
    } else {
      data = decoder.outputBuffer.sublist(0);
      energy = Float32FrameEnergy.calculate(data);
    }
    return new AnalyzedAudio(data, energy);
  }

  @override
  Stream<AnalyzedAudio> bind(Stream<Uint8List> stream) async* {
    BufferedOpusDecoder decoder = new BufferedOpusDecoder(
        sampleRate: analyzeSampleRate,
        channels: analyzeChannels,
        maxOutputBufferSizeBytes:
            _maxSamplesPerPacket(analyzeSampleRate, analyzeChannels) * 4);
    await for (Uint8List opusPacket in stream) {
      yield calculate(opusPacket, decoder, passthroughPacket);
    }
    decoder.destroy();
  }
}

int _maxSamplesPerPacket(int sampleRate, int channels) =>
    ((sampleRate * channels * 120) / 1000).ceil();
