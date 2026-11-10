import 'package:flutter_test/flutter_test.dart';
import 'package:utterleaf_mobile/sound_wave.dart';

void main() {
  test('measurement-mode speech fills the wave while noise stays low', () {
    // About -35 dBFS speech and -58 dBFS room noise in iOS measurement mode.
    expect(AudioEnvelope.target(0.0178), greaterThan(0.55));
    expect(AudioEnvelope.target(0.00126), lessThan(0.08));
    expect(AudioEnvelope.target(0), 0);
    expect(AudioEnvelope.target(1), 1);
  });

  test('envelope rises quickly, decays, and stays bounded', () {
    final envelope = AudioEnvelope();
    for (var i = 0; i <= 20; i++) {
      envelope.append(0.03, i * 0.02);
    }
    final loud = envelope.amplitudes(0.475, count: 8, window: 0.4);
    expect(loud.last, greaterThan(0.6));
    expect(loud.every((v) => v >= 0 && v <= 1), isTrue);
    final later = envelope.amplitudes(1.4, count: 8, window: 0.4);
    expect(later.last, lessThan(loud.last * 0.1));
    envelope.reset();
    expect(envelope.amplitudes(1, count: 4), [0, 0, 0, 0]);
  });

  test('three layers keep Mac strengths and zero at both ends', () {
    final samples = List<double>.filled(32, 1);
    for (var layer = 0; layer < 3; layer++) {
      final points = SpeechWaveCurve.points(samples, 0.7, layer);
      expect(points.first.abs(), lessThan(1e-9));
      expect(points.last.abs(), lessThan(1e-9));
      final peak = points.map((v) => v.abs()).reduce((a, b) => a > b ? a : b);
      expect(peak, lessThanOrEqualTo(SpeechWaveCurve.strengths[layer] + 1e-9));
      expect(peak, greaterThan(SpeechWaveCurve.strengths[layer] * 0.8));
    }
    expect(
      SpeechWaveCurve.points(List.filled(32, 0), 0, 0).every((v) => v == 0),
      isTrue,
    );
  });
}
