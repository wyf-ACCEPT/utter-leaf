import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Dart port of the Mac `AudioEnvelope`: a bounded, time-based amplitude
/// history. It stores no audio or speech content.
class AudioEnvelope {
  /// iOS records in `.measurement` mode (no automatic gain), which reads about
  /// 12 dB quieter than the Mac input path, so the visual floor sits lower.
  static const floorDb = -62.0;
  static const rangeDb = 40.0;

  final List<({double time, double level})> _points = [];
  double _smoothed = 0;

  void reset() {
    _points.clear();
    _smoothed = 0;
  }

  static double target(double rms) {
    final db = 20 * math.log(math.max(rms, 0.000001)) / math.ln10;
    // Ignore the near-silence noise floor before visual gain is applied.
    final unit = ((db - floorDb) / rangeDb).clamp(0.0, 1.0);
    return math.pow(unit, 1.25).toDouble();
  }

  void append(double rms, double time) {
    if (!rms.isFinite || !time.isFinite) return;
    appendLevel(target(rms), time);
  }

  /// Appends an already normalised 0...1 level (used when only the coarse
  /// snapshot level is available).
  void appendLevel(double value, double time) {
    if (_points.isNotEmpty && time < _points.last.time) reset();
    final previous = _points.isEmpty ? time - 0.04 : _points.last.time;
    final dt = (time - previous).clamp(0.001, 0.25);
    final tau = value > _smoothed ? 0.035 : 0.16;
    _smoothed += (value - _smoothed) * (1 - math.exp(-dt / tau));
    _points.add((time: time, level: _smoothed));
    _points.removeWhere((p) => p.time < time - 1.6);
    if (_points.length > 128) _points.removeRange(0, _points.length - 128);
  }

  List<double> amplitudes(double time, {int count = 32, double window = 0.4}) {
    if (count <= 0) return const [];
    if (_points.isEmpty) return List.filled(count, 0);
    final first = _points.first, last = _points.last;
    var cursor = 0;
    // A small presentation delay lets rendering interpolate between samples.
    final end = time - 0.075;
    return List.generate(count, (index) {
      final moment =
          end - window + (count == 1 ? 1 : index / (count - 1)) * window;
      if (moment + 1e-9 < first.time) return 0.0;
      if (moment >= last.time) {
        return last.level * math.exp(-math.max(moment - last.time, 0) / 0.16);
      }
      while (cursor + 1 < _points.length && _points[cursor + 1].time < moment) {
        cursor++;
      }
      final a = _points[cursor];
      final b = _points[math.min(cursor + 1, _points.length - 1)];
      final weight = ((moment - a.time) / math.max(b.time - a.time, 0.001))
          .clamp(0.0, 1.0);
      return (a.level + (b.level - a.level) * weight).clamp(0.0, 1.0);
    });
  }
}

/// Dart port of the Mac `SpeechWaveCurve`. Microphone amplitude controls the
/// height; only the phase motion is decorative.
class SpeechWaveCurve {
  static const frequencies = [1.6, 2.15, 2.7];
  static const strengths = [0.95, 0.57, 0.33];

  static List<double> points(
    List<double> amplitudes,
    double phase,
    int layer, {
    int count = 96,
  }) {
    if (count < 2) return const [];
    final l = layer.clamp(0, 2);
    final last = math.max(amplitudes.length - 1, 0);
    return List.generate(count, (index) {
      final x = index / (count - 1);
      final position = x * last;
      final low = math.min(position.floor(), last);
      final high = math.min(low + 1, last);
      final a = amplitudes.isEmpty ? 0.0 : amplitudes[low];
      final b = amplitudes.isEmpty ? 0.0 : amplitudes[high];
      final amplitude = ((a + (b - a) * (position - low)) * 1.7).clamp(
        0.0,
        1.0,
      );
      final envelope = math.max(0.0, 1 - math.pow(2 * x - 1, 2));
      return envelope *
          amplitude *
          strengths[l] *
          math.sin(2 * math.pi * frequencies[l] * x + phase);
    });
  }
}

/// Three-layer live waveform matching the Mac recording view. It polls the
/// native meter at about 30 Hz while visible and falls back to the coarse
/// snapshot level when the meter is unavailable.
class SoundWave extends StatefulWidget {
  const SoundWave({
    super.key,
    required this.level,
    required this.channel,
    required this.color,
  });
  final double level;
  final Color color;
  final MethodChannel channel;
  @override
  State<SoundWave> createState() => _SoundWaveState();
}

class _SoundWaveState extends State<SoundWave>
    with SingleTickerProviderStateMixin {
  final envelope = AudioEnvelope();
  late final Ticker ticker;
  final clock = Stopwatch()..start();
  double nativeNow = 0, nativeAt = 0, lastSample = 0, lastPoll = -1;
  bool polling = false, meterAvailable = true;
  double get now => nativeNow + clock.elapsedMicroseconds / 1e6 - nativeAt;

  @override
  void initState() {
    super.initState();
    ticker = createTicker(_tick)..start();
  }

  void _tick(Duration _) {
    final local = clock.elapsedMicroseconds / 1e6;
    if (!polling && local - lastPoll >= 1 / 30) {
      lastPoll = local;
      _poll();
    }
    setState(() {});
  }

  Future<void> _poll() async {
    if (!meterAvailable) {
      envelope.appendLevel(widget.level.clamp(0.0, 1.0), now);
      return;
    }
    polling = true;
    try {
      final value = await widget.channel.invokeMapMethod<String, dynamic>(
        'meter',
      );
      final samples = value?['samples'] as List?;
      if (value == null || samples == null) {
        meterAvailable = false;
        return;
      }
      nativeNow = (value['now'] as num).toDouble();
      nativeAt = clock.elapsedMicroseconds / 1e6;
      for (final sample in samples) {
        final time = (sample[0] as num).toDouble();
        if (time <= lastSample) continue;
        lastSample = time;
        envelope.append((sample[1] as num).toDouble(), time);
      }
    } catch (_) {
      meterAvailable = false;
    } finally {
      polling = false;
    }
  }

  @override
  void dispose() {
    ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final t = now;
    return CustomPaint(
      painter: _WavePainter(
        envelope.amplitudes(t, count: 32, window: 0.4),
        still ? 0 : t,
        widget.color,
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.samples, this.time, this.color);
  final List<double> samples;
  final double time;
  final Color color;
  static const speeds = [3.4, -2.8, 4.1];
  static const opacities = [0.95, 0.42, 0.2];

  @override
  void paint(Canvas canvas, Size size) {
    for (var layer = 2; layer >= 0; layer--) {
      final phase = time == 0 ? 0.0 : time * speeds[layer] + layer * 0.8;
      final values = SpeechWaveCurve.points(samples, phase, layer);
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final x = size.width * i / (values.length - 1);
        final y = size.height * (0.5 - values[i] * 0.47);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = layer == 0 ? 2.6 : 1.6
          ..color = color.withValues(alpha: opacities[layer]),
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}
