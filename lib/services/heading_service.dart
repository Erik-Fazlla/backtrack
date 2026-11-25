import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../core/angles.dart';

/// Which way the top of the phone points (compass sensor), smoothed.
/// Works standing still and without GPS. On only while the app is open.
class HeadingService extends ChangeNotifier {
  HeadingService({Stream<(double?, double?)> Function()? source})
      : _source = source ?? _defaultSource;

  /// (heading, accuracy) in degrees.
  final Stream<(double?, double?)> Function() _source;

  static Stream<(double?, double?)> _defaultSource() =>
      (FlutterCompass.events ?? const Stream<CompassEvent>.empty())
          .map((e) => (e.heading, e.accuracy));

  StreamSubscription<(double?, double?)>? _sub;
  double? _heading;
  double? _accuracy;
  double _lastNotified = -999;

  /// Degrees clockwise from north, or null (no compass / not started).
  double? get heading => _heading;

  /// Reported error in degrees (rough on Android), or null.
  double? get accuracyDeg => _accuracy;

  bool get running => _sub != null;

  void start() {
    if (_sub != null) return;
    _sub = _source().listen((e) {
      final (h, acc) = e;
      if (h == null) return;
      _heading = smoothAngle(_heading, h, 0.25);
      _accuracy = acc;
      // Redraw only for visible changes (sensor fires ~20-60x a second).
      var d = (_heading! - _lastNotified).abs() % 360;
      if (d > 180) d = 360 - d;
      if (d >= 1.5) {
        _lastNotified = _heading!;
        notifyListeners();
      }
    }, onError: (Object e) => debugPrint('[compass] $e'));
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
