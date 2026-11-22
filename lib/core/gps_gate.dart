import 'geo.dart';

/// Holds recording back until the GPS has settled.
///
/// Right after GPS turns on, positions slide around for a while (sometimes
/// 20-50 m) while the chip locks onto satellites, even though it may already
/// report a small accuracy number. Trusting those first fixes draws a line
/// you never walked. We wait for [requiredFixes] consecutive good fixes that
/// sit within [maxSpreadM] of each other.
class GpsWarmup {
  GpsWarmup({
    this.requiredFixes = 5,
    this.maxAccuracyM = 15,
    this.maxSpreadM = 10,
  });

  final int requiredFixes;
  final double maxAccuracyM;
  final double maxSpreadM;

  final List<TrackPoint> _window = [];
  bool _ready = false;
  bool get ready => _ready;

  /// Fixes collected toward readiness (for a progress hint in the UI).
  int get progress => _window.length;

  bool feed(TrackPoint p) {
    if (_ready) return true;
    if (p.accuracyM > maxAccuracyM) {
      _window.clear();
      return false;
    }
    _window.add(p);
    if (_window.length > requiredFixes) _window.removeAt(0);
    if (_window.length < requiredFixes) return false;
    for (var i = 0; i < _window.length; i++) {
      for (var j = i + 1; j < _window.length; j++) {
        if (distanceBetween(_window[i], _window[j]) > maxSpreadM) {
          return false;
        }
      }
    }
    _ready = true;
    return true;
  }

  /// Skip warm-up (resuming a session that already had a settled fix).
  void markReady() => _ready = true;

  void reset() {
    _window.clear();
    _ready = false;
  }
}

/// Doppler speed under this = standing still. GPS position drifts a few
/// metres while you stand, but its speed reading stays near zero.
const double stationarySpeedMps = 0.5;

bool isMoving(TrackPoint p) {
  final s = p.speedMps;
  if (s == null || s < 0) return true;
  return s >= stationarySpeedMps;
}
