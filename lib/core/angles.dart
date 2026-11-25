/// Low-pass filter for compass headings (degrees, 0..360) that takes the
/// short way round north, so 350 -> 10 doesn't swing through 180.
/// [alpha] = how much of the new reading to take (0..1).
double smoothAngle(double? previous, double next, double alpha) {
  if (previous == null) return next % 360;
  var diff = (next - previous) % 360;
  if (diff > 180) diff -= 360;
  if (diff < -180) diff += 360;
  return (previous + alpha * diff) % 360;
}

/// Width of the direction beam: wide when the compass is unsure (like
/// Google Maps), narrow when it is confident. [accuracyDeg] is the sensor's
/// reported error; null = unknown.
double beamWidthDeg(double? accuracyDeg) {
  if (accuracyDeg == null) return 60;
  return (accuracyDeg * 2).clamp(30, 100).toDouble();
}
