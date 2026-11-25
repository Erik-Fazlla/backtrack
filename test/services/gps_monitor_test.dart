import 'dart:async';

import 'package:backtrack/core/geo.dart';
import 'package:backtrack/core/gps_readiness.dart';
import 'package:backtrack/services/gps_monitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 10);
  late DateTime now;
  late StreamController<TrackPoint> gps;

  setUp(() {
    now = t0;
    gps = StreamController<TrackPoint>.broadcast();
  });
  tearDown(() => gps.close());

  TrackPoint fix(int s) => TrackPoint(
      lat: 38, lon: 23.7, accuracyM: 4, time: t0.add(Duration(seconds: s)));

  test('no permission: does not start, says so', () async {
    final m = GpsMonitor(
        positions: () => gps.stream,
        hasPermission: () async => false,
        serviceEnabled: () => const Stream<bool>.empty(),
        now: () => now);
    await m.start();
    expect(m.running, isFalse);
    expect(m.noPermission, isTrue);
    m.dispose();
  });

  test('Location switch off: says so, restarts when turned on', () async {
    final service = StreamController<bool>.broadcast();
    var starts = 0;
    final m = GpsMonitor(
      positions: () {
        starts++;
        return starts == 1
            ? Stream<TrackPoint>.error(const LocationServiceDisabledException())
            : gps.stream;
      },
      hasPermission: () async => true,
      serviceEnabled: () => service.stream,
      now: () => now,
    );
    await m.start();
    await Future<void>.delayed(Duration.zero);
    expect(m.locationOff, isTrue);
    expect(m.running, isFalse);

    service.add(true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(m.locationOff, isFalse);
    expect(m.running, isTrue);
    expect(starts, 2);
    await m.stop();
    await service.close();
    m.dispose();
  });

  test('searching -> settling -> ready as steady fixes arrive', () async {
    final m = GpsMonitor(
        positions: () => gps.stream,
        hasPermission: () async => true,
        serviceEnabled: () => const Stream<bool>.empty(),
        now: () => now);
    await m.start();
    expect(m.running, isTrue);
    expect(m.signal, GpsSignal.searching);

    gps.add(fix(0));
    await Future<void>.delayed(Duration.zero);
    expect(m.signal, GpsSignal.settling);
    expect(m.accuracyM, 4);

    for (var s = 1; s <= 10; s++) {
      gps.add(fix(s));
    }
    now = t0.add(const Duration(seconds: 10));
    await Future<void>.delayed(Duration.zero);
    expect(m.signal, GpsSignal.ready);
    expect(m.recent.length, 11);

    await m.stop();
    expect(m.running, isFalse);
    m.dispose();
  });
}
