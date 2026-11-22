import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/geo.dart';
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
  })  : _now = now ?? DateTime.now,
        _filter = filter ?? PointFilter();

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

  Future<void> start() async {
    _points.clear();
    _distanceM = 0;
    _filter.reset();
    _startedAt = _now();
    await store.startSession(_startedAt!);
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
    for (final p in _points) {
      _filter.accept(p);
    }
    if (s.finished) {
      _state = RecState.stopped;
      notifyListeners();
      return false;
    }
    store.resume(s.file);
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
    if (_filter.accept(p)) {
      if (_points.isNotEmpty) _distanceM += distanceBetween(_points.last, p);
      _points.add(p);
      _state = RecState.recording;
      _writes = _writes.then((_) => store.append(p));
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
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
