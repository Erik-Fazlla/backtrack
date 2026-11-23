import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backtrack/core/geo.dart';
import 'package:backtrack/services/recorder.dart';
import 'package:backtrack/services/track_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replays REAL walks recorded on the phone through the current pipeline.
///
/// 1. Copy raw_*.jsonl files from the phone into test/real_logs/
///    (phone path: Android/data/com.erikfazlla.backtrack/files/sessions,
///    or use the app's Share GPS log button).
/// 2. flutter test test/real_logs_test.dart
/// 3. Open test/real_logs/out/*.gpx in https://gpx.studio to compare the
///    raw fixes against the processed trail on a map.
///
/// test/real_logs/ is git-ignored: logs contain where you walk.
void main() {
  final dir = Directory('test/real_logs');
  final logs = dir.existsSync()
      ? (dir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.uri.pathSegments.last.startsWith('raw_') &&
              f.path.endsWith('.jsonl'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];

  if (logs.isEmpty) {
    test('no real logs present (drop raw_*.jsonl in test/real_logs/)', () {});
    return;
  }

  for (final log in logs) {
    final name = log.uri.pathSegments.last.replaceAll('.jsonl', '');
    test('replay $name', () async {
      final raw = <TrackPoint>[];
      Map<String, Object?> meta = const {};
      for (final line in log.readAsLinesSync()) {
        if (line.trim().isEmpty) continue;
        try {
          final j = jsonDecode(line) as Map<String, Object?>;
          if (j.containsKey('meta')) {
            meta = (j['meta'] as Map).cast<String, Object?>();
          } else {
            raw.add(TrackPoint.fromJson(j));
          }
        } on FormatException {
          // torn last line
        }
      }

      final tmp = Directory.systemTemp.createTempSync('bt_real');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final gps = StreamController<TrackPoint>.broadcast();
      final rec = Recorder(store: TrackStore(tmp), positions: () => gps.stream);
      await rec.start();
      for (final p in raw) {
        gps.add(p);
      }
      await Future<void>.delayed(Duration.zero);
      await rec.stop();
      await gps.close();

      final out = Directory('test/real_logs/out')..createSync(recursive: true);
      File('${out.path}/$name.raw.gpx').writeAsStringSync(_gpx('$name raw', raw));
      File('${out.path}/$name.trail.gpx')
          .writeAsStringSync(_gpx('$name trail', rec.points));

      final pts = rec.points;
      final moving = raw.where((p) => (p.speedMps ?? 1) >= 0.5).length;
      final accs = raw.map((p) => p.accuracyM).toList()..sort();
      // ignore: avoid_print
      print([
        '── $name  (gps: ${meta['gpsMode'] ?? '?'})',
        'raw fixes: ${raw.length}  (moving $moving, accuracy median '
            '${accs.isEmpty ? '-' : accs[accs.length ~/ 2].toStringAsFixed(1)} m)',
        'raw path length: ${trailDistance(raw).toStringAsFixed(0)} m',
        'trail points: ${pts.length}  distance: ${rec.distanceM.toStringAsFixed(0)} m',
        'max gap: ${maxGap(pts).toStringAsFixed(1)} m',
        if (pts.length > 1)
          'start→end gap: ${distanceBetween(pts.first, pts.last).toStringAsFixed(1)} m',
        'first trail point after ${pts.isEmpty || raw.isEmpty ? '-' : pts.first.time.difference(raw.first.time).inSeconds} s',
      ].join('\n'));
    });
  }
}

String _gpx(String name, List<TrackPoint> pts) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<gpx version="1.1" creator="backtrack" '
        'xmlns="http://www.topografix.com/GPX/1/1">')
    ..writeln('<trk><name>$name</name><trkseg>');
  for (final p in pts) {
    b.write('<trkpt lat="${p.lat}" lon="${p.lon}">');
    if (p.altitudeM != null) b.write('<ele>${p.altitudeM}</ele>');
    b.writeln('<time>${p.time.toUtc().toIso8601String()}</time></trkpt>');
  }
  b.writeln('</trkseg></trk></gpx>');
  return b.toString();
}
