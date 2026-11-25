import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/geo.dart';
import '../core/gps_gate.dart';
import '../core/kalman.dart';
import '../core/point_filter.dart';
import 'track_store.dart';

enum RecState { idle, waitingForFix, recording, stopped }

/// Recording state machine:
/// idle -> waitingForFix -> recording -> stopped.
class Recorder extends ChangeNotifier {
  Recorder({
    required this.store,
    required this.positions,
    DateTime Function()? now,
    PointFilter? filter,
    this.minSpacingM = 5,
    PositionSmoother? smoother,
    GpsWarmup? warmup,
    this.sessionMeta,
  })  : _now = now ?? DateTime.now,
        _filter = filter ?? PointFilter(),
        _smoother = smoother ?? PositionSmoother(),
        // Stricter than before: ~8 s of fixes <= 8 m that agree within
        // 6 m. Phones report small accuracy while still sliding into place.
        _warmup = warmup ??
            GpsWarmup(requiredFixes: 8, maxAccuracyM: 8, maxSpreadM: 6);

  final GpsWarmup _warmup;

  /// Fallback rule (5 fixes <= 15 m within 10 m) used after [_maxStrictWait].
  final GpsWarmup _looseWarmup = GpsWarmup();
  static const _maxStrictWait = Duration(seconds: 30);
  DateTime? _firstWarmupFix;

  /// Written as the first line of each raw log (e.g. GPS mode used).
  final Map<String, Object?> Function()? sessionMeta;

  /// How many settled fixes we have while waiting for GPS (UI hint).
  int get warmupProgress => _warmup.progress;
  int get warmupRequired => _warmup.requiredFixes;

  bool _moving = false;
  /// False while GPS says you are standing still (trail is paused).
  bool get moving => _moving;

  /// Save a smoothed point only after moving this far from the last one.
  final double minSpacingM;
  final PositionSmoother _smoother;

  final TrackStore store;
  final Stream<TrackPoint> Function() positions;
  final DateTime Function() _now;
  final PointFilter _filter;

  RecState _state = RecState.idle;
  RecState get state => _state;

  final List<TrackPoint> _points = [];
  List<TrackPoint> get points => List.unmodifiable(_points);

  TrackPoint? _latest;
  /// Latest raw fix (even rejected ones) for the "you are here" dot.
  TrackPoint? get latest => _latest;
  double? get lastAccuracyM => _latest?.accuracyM;

  double _distanceM = 0;
  double get distanceM => _distanceM;

  DateTime? _startedAt;
  DateTime? get startedAt => _startedAt;

  StreamSubscription<TrackPoint>? _sub;
  Object? _error;
  Object? get error => _error;

  /// [gpsReady]: the warm-up indicator was already green, so the GPS has
  /// settled; record from the first fix. [prelude]: fixes seen while
  /// warming up, written to the raw GPS log for diagnosis.
  Future<void> start(
      {bool gpsReady = false, List<TrackPoint> prelude = const []}) async {
    _points.clear();
    _lastGood = null;
    _recent.clear();
    _distanceM = 0;
    _filter.reset();
    _smoother.reset();
    _warmup.reset();
    _looseWarmup.reset();
    _firstWarmupFix = null;
    if (gpsReady) _warmup.markReady();
    _startedAt = _now();
    await store.startSession(_startedAt!,
        meta: sessionMeta?.call(), prelude: prelude);
    _state = RecState.waitingForFix;
    _listen();
    notifyListeners();
  }

  /// Reload the latest session after an app restart.
  /// Returns true if an unfinished session was resumed.
  Future<bool> restore() async {
    final s = await store.loadLatest();
    if (s == null || s.points.isEmpty) return false;
    _points
      ..clear()
      ..addAll(s.points);
    _distanceM = trailDistance(_points);
    _startedAt = _points.first.time;
    _filter.reset();
    _smoother.reset();
    for (final p in _points) {
      _filter.accept(p);
      _smoother.update(p);
    }
    if (s.finished) {
      _state = RecState.stopped;
      notifyListeners();
      return false;
    }
    store.resume(s.file);
    // Already had a settled fix before the restart: no warm-up needed.
    _warmup.markReady();
    _state = RecState.recording;
    _listen();
    notifyListeners();
    return true;
  }

  void _listen() {
    _sub?.cancel();
    _error = null;
    _sub = positions().listen(_onFix, onError: (Object e) {
      _error = e;
      notifyListeners();
    });
  }

  /// Disk writes are chained so points land in order even when fixes
  /// arrive faster than the file system flushes.
  Future<void> _writes = Future.value();

  /// Completes when every accepted point is on disk.
  Future<void> idle() => _writes;

  void _onFix(TrackPoint p) {
    if (_state != RecState.waitingForFix && _state != RecState.recording) {
      return;
    }
    _latest = p;
    _writes = _writes.then((_) => store.appendRaw(p)); // diagnosis log

    // 0. wait until the GPS has settled (no lines drawn while it converges)
    if (!_warmup.ready) {
      _firstWarmupFix ??= p.time;
      final strict = _warmup.feed(p);
      final loose = _looseWarmup.feed(p);
      // Never block forever: under trees accuracy can stay at +-10-15 m.
      // After 30 s of fixes, the looser old rule is good enough.
      final waitedLong =
          p.time.difference(_firstWarmupFix!) >= _maxStrictWait;
      if (strict || (loose && waitedLong)) {
        _warmup.markReady();
        _filter.reset();
        _smoother.reset();
      } else {
        notifyListeners();
        return;
      }
    }
    // 1. drop bad fixes (poor accuracy, impossible jumps) on the raw data
    if (_filter.accept(p)) {
      _recent.add(p);
      while (_recent.isNotEmpty &&
          p.time.difference(_recent.first.time) > _moveWindow) {
        _recent.removeAt(0);
      }
      // Doppler speed says still, but some phones (seen with Google/fused
      // location) report ~0 m/s while you walk. Real displacement over the
      // last 10 s overrides it; standing-still drift rarely gets that far.
      _moving = isMoving(p) || _displacedSteadily();
      final last = _points.isEmpty ? null : _points.last;
      // 2. standing still: GPS drifts but Doppler speed is ~0 -> freeze
      if (last != null && !_moving) {
        notifyListeners();
        return;
      }
      // 3. smooth jitter
      final s = _smoother.update(p);
      _latest = s;
      _lastGood = s;
      // 4. save only after real movement
      if (last == null || distanceBetween(last, s) >= minSpacingM) {
        if (last != null) _distanceM += distanceBetween(last, s);
        _points.add(s);
        _state = RecState.recording;
        _writes = _writes.then((_) => store.append(s));
      }
    }
    notifyListeners();
  }

  /// Latest smoothed position that passed the filters, saved or not.
  TrackPoint? _lastGood;

  /// Recent accepted raw fixes, for the displacement-based moving check.
  final List<TrackPoint> _recent = [];
  static const _moveWindow = Duration(seconds: 10);
  static const double _moveWindowMinM = 10;

  /// Moved at least 10 m in the last 10 s, in a fairly straight line (net
  /// distance >= 80 % of the path). Standing-still drift zig-zags, so its
  /// net displacement is a small share of its path.
  bool _displacedSteadily() {
    if (_recent.length < 3) return false;
    final net = distanceBetween(_recent.first, _recent.last);
    if (net < _moveWindowMinM) return false;
    var path = 0.0;
    for (var i = 1; i < _recent.length; i++) {
      path += distanceBetween(_recent[i - 1], _recent[i]);
    }
    return net >= 0.8 * path;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    // The last few metres are usually under the spacing threshold and would
    // be lost, leaving the loop open. Save where we really ended.
    final end = _lastGood;
    if (end != null && _points.isNotEmpty) {
      final d = distanceBetween(_points.last, end);
      if (d >= 1) {
        _distanceM += d;
        _points.add(end);
        _writes = _writes.then((_) => store.append(end));
      }
    }
    _lastGood = null;
    _state = RecState.stopped;
    notifyListeners(); // UI flips at once; disk work follows
    await _writes;
    await store.finish();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
