import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

class VadViz extends StatefulWidget {
  final VadVizPainter painter;
  const VadViz({required this.painter, super.key});

  @override
  State<VadViz> createState() => _VadVizState();
}

class _VadVizState extends State<VadViz> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          painter: widget.painter,
          size: const Size(double.infinity, 150.0),
        ),
        Slider(
          value: widget.painter.vadMin,
          onChanged: (double newVal) {
            if (newVal < widget.painter.vadMax) {
              widget.painter.vadMin = newVal;
              setState(() {});
            }
          },
          min: 0.0,
          max: 1.0,
          activeColor: Colors.red,
        ),
        Slider(
          value: widget.painter.vadMax,
          onChanged: (double newVal) {
            if (newVal > widget.painter.vadMin) {
              widget.painter.vadMax = newVal;
              setState(() {});
            }
          },
          min: 0.0,
          max: 1.0,
          activeColor: Colors.yellow,
        )
      ],
    );
  }
}

class VadVizPainter extends CustomPainter implements StreamConsumer<double> {
  final double strokeWidth;
  final double strokeSpacing;
  final List<double> _values;
  final ChangeNotifier _notifier;

  double _vadMin;
  set vadMin(double value) {
    _vadMin = value;
    repaint();
  }

  double get vadMin => _vadMin;

  double _vadMax;
  set vadMax(double value) {
    _vadMax = value;
    repaint();
  }

  double get vadMax => _vadMax;

  int _maxStokes;

  factory VadVizPainter(
      {double vadMin = 0.34,
      double vadMax = 0.67,
      double strokeWidth = 2.0,
      double strokeSpacing = 1.5}) {
    return VadVizPainter._(
        vadMax, vadMin, strokeWidth, strokeSpacing, ChangeNotifier());
  }

  VadVizPainter._(
    this._vadMax,
    this._vadMin,
    this.strokeWidth,
    this.strokeSpacing,
    ChangeNotifier notifier,
  )   : _notifier = notifier,
        _values = [],
        _maxStokes = 0,
        super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    Paint p = Paint();
    p.strokeWidth = strokeWidth;
    p.style = PaintingStyle.fill;
    p.color = Colors.green;
    canvas.drawRect(Offset.zero & size, p);
    p.color = Colors.yellow;
    canvas.drawRect(
        Rect.fromLTWH(0.0, size.height * (1 - _vadMax) * 0.5, size.width,
            size.height * _vadMax),
        p);
    p.color = Colors.red;
    canvas.drawRect(
        Rect.fromLTWH(0.0, size.height * (1 - _vadMin) * 0.5, size.width,
            size.height * _vadMin),
        p);
    p.color = Colors.black;
    double right = size.width;
    int index = _values.length - 1;
    while (right > 0 && index >= 0) {
      double height = _values[index] * size.height;
      double top = size.height * 0.5 + height * 0.5;
      canvas.drawRect(
          Rect.fromLTRB(right - strokeWidth, top, right, top - height), p);
      right -= strokeWidth;
      right -= strokeSpacing;
      index--;
    }
    if (right <= 0) {
      _maxStokes = max(_maxStokes, _values.length - index);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) =>
      oldDelegate != this;

  @override
  Future addStream(Stream<double> stream) async {
    await for (double value in stream) {
      if (_maxStokes > 0 && _values.length >= _maxStokes) {
        _values.removeAt(0);
        _values.add(value);
      } else {
        _values.add(value);
      }
      repaint();
    }
  }

  void repaint() {
    _notifier
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        .notifyListeners();
  }

  void clear() {
    _values.clear();
    repaint();
  }

  @override
  Future close() async {}
}
