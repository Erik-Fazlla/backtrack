import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/geo.dart';
import '../core/gps_readiness.dart';

/// Warms the GPS up before you press Record (like Strava's GPS bar), so the
/// chip has settled by the time recording starts, and reports how ready it
/// is. Runs only while the app is open and not recording.
class GpsMonitor extends ChangeNotifier {
  GpsMonitor({
    required this.positions,
    Future<bool> Function()? hasPermission,
    Stream<bool> Function()? serviceEnabled,
    DateTime Function()? now,
  }) : _hasPermission = hasPermission ?? _defaultPermission,
       _serviceEnabled = serviceEnabled ?? _defaultServiceStream,
       _now = now ?? DateTime.now;

  /// Foreground-only position stream (no notification).
  final Stream<TrackPoint> Function() positions;
  final Future<bool> Function() _hasPermission;

  /// Emits when the phone's Location switch is turned on/off.
  final Stream<bool> Function() _serviceEnabled;
  StreamSubscription<bool>? _serviceSub;
  bool _wanted = false;
  bool _locationOff = false;

  /// The phone's Location switch is off: no GPS at all until it's on.
  bool get locationOff => _locationOff;
  final DateTime Function() _now;

  StreamSubscription<TrackPoint>? _sub;
  Timer? _tick;
  GpsReadiness? _readiness;
  bool _noPermission = false;

  bool get running => _sub != null;

  /// True when location permission hasn't been given yet (tap Record).
  bool get noPermission => _noPermission;

  GpsSignal get signal => _readiness?.status(_now()) ?? GpsSignal.searching;

  double? get accuracyM => _readiness?.lastAccuracyM;

  Duration get searchingFor =>
      _readiness?.searchingFor(_now()) ?? Duration.zero;

  /// Warm-up fixes from the last 2 minutes (written to the GPS log).
  List<TrackPoint> get recent => _readiness?.recent ?? const [];

  static Stream<bool> _defaultServiceStream() =>
      Geolocator.getServiceStatusStream().map(
        (s) => s == ServiceStatus.enabled,
      );

  static Future<bool> _defaultPermission() async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  Future<void> start() async {
    _wanted = true;
    // Restart by itself when the user turns Location back on.
    _serviceSub ??= _serviceEnabled().listen((on) {
      _locationOff = !on;
      if (on && _wanted && !running) start();
      notifyListeners();
    });
    if (running) return;
    if (!await _hasPermission()) {
      _noPermission = true;
      notifyListeners();
      return;
    }
    _noPermission = false;
    _readiness = GpsReadiness(startedAt: _now());
    _sub = positions().listen(
      (p) {
        _readiness?.add(p);
        notifyListeners();
      },
      onError: (Object e) {
        debugPrint('[gps] warm-up error: $e');
        if (e is LocationServiceDisabledException) {
          _locationOff = true;
          _sub?.cancel();
          _sub = null;
          _tick?.cancel();
          _tick = null;
          notifyListeners();
        }
      },
    );
    // Re-evaluate every second so "searching 12 s" counts and a stalled
    // stream drops back to searching.
    _tick = Timer.periodic(
      const Duration(seconds: 1),
      (_) => notifyListeners(),
    );
    notifyListeners();
  }

  Future<void> stop() async {
    _wanted = false;
    await _serviceSub?.cancel();
    _serviceSub = null;
    await _sub?.cancel();
    _sub = null;
    _tick?.cancel();
    _tick = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _serviceSub?.cancel();
    _sub?.cancel();
    _tick?.cancel();
    super.dispose();
  }
}
