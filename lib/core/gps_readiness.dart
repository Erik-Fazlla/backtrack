import 'dart:math' as math;

import 'geo.dart';

/// What the GPS indicator shows before / at the start of a recording.
enum GpsSignal {
  /// No position at all yet (or none for 5 s).
  searching,

  /// Positions arrive but are inaccurate or still sliding into place.
  settling,

  /// Accurate and steady for [GpsReadiness.window]: safe to start.
  ready,
}

/// Judges whether the GPS has really settled.
///
/// Phones report a small accuracy ("+-4 m") while the position is still
/// sliding 20-50 m toward the real spot during warm-up. So "ready" needs
/// every fix of the last [window] to be accurate ([maxAccuracyM]) AND all
/// of them to sit close together ([maxSpreadM] from their centre).
/// Assumes you stand still at the start while waiting, as instructed.
class GpsReadiness {
  GpsReadiness({
    required this.startedAt,
    this.window = const Duration(seconds: 10),
    this.minFixes = 8,
    this.maxAccuracyM = 8,
    this.maxSpreadM = 6,
    this.keep = const Duration(minutes: 2),
  });

  final DateTime startedAt;
  final Duration window;
  final int minFixes;
  final double maxAccuracyM;
  final double maxSpreadM;

  /// How much history to keep (written to the GPS log at Record).
  final Duration keep;

  final List<TrackPoint> _recent = [];
  List<TrackPoint> get recent => List.unmodifiable(_recent);

  double? get lastAccuracyM => _recent.isEmpty ? null : _recent.last.accuracyM;


  void add(TrackPoint p) {
    _recent.add(p);
    while (_recent.isNotEmpty && p.time.difference(_recent.first.time) > keep) {
      _recent.removeAt(0);
    }
  }

  /// How long we have been waiting for a first fix (UI hint).
  /// How long without a fresh fix: since start when none came yet, else
  /// since the last one (a single cached fix then silence shouldn't read
  /// "searching 0 s").
  Duration searchingFor(DateTime now) {
    final d = now.difference(_recent.isEmpty ? startedAt : _recent.last.time);
    return d.isNegative ? Duration.zero : d;
  }

  GpsSignal status(DateTime now) {
    if (_recent.isEmpty ||
        now.difference(_recent.last.time) > const Duration(seconds: 5)) {
      return GpsSignal.searching;
    }
    final from = now.subtract(window);
    final win = _recent.where((p) => !p.time.isBefore(from)).toList();
    if (win.length < minFixes) return GpsSignal.settling;
    // The window must really span ~[window], not just a burst of fixes.
    if (win.last.time.difference(win.first.time) <
        window - const Duration(seconds: 1)) {
      return GpsSignal.settling;
    }
    if (win.any((p) => p.accuracyM > maxAccuracyM)) return GpsSignal.settling;
    final cLat = win.map((p) => p.lat).reduce((a, b) => a + b) / win.length;
    final cLon = win.map((p) => p.lon).reduce((a, b) => a + b) / win.length;
    var spread = 0.0;
    for (final p in win) {
      spread = math.max(spread, distanceMeters(cLat, cLon, p.lat, p.lon));
    }
    return spread <= maxSpreadM ? GpsSignal.ready : GpsSignal.settling;
  }
}
