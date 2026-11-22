import 'dart:convert';
import 'dart:io';

import '../core/geo.dart';

class StoredSession {
  StoredSession(this.points, {required this.finished, required this.file});
  final List<TrackPoint> points;
  final bool finished;
  final File file;
}

/// Crash-safe storage for M0: one append-only JSON-lines file per session.
/// Every point is flushed to disk as it arrives, so a killed app loses
/// at most the point being written. (Replaced by drift/SQLite in M1.)
class TrackStore {
  TrackStore(this.dir);

  final Directory dir;
  File? _current;
  File? _raw;

  static String _stamp(DateTime t) {
    final u = t.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}_'
        '${two(u.hour)}${two(u.minute)}${two(u.second)}';
  }

  Future<void> startSession(DateTime start) async {
    await dir.create(recursive: true);
    _current = File('${dir.path}/session_${_stamp(start)}.jsonl');
    _raw = File('${dir.path}/raw_${_stamp(start)}.jsonl');
    await _current!.writeAsString('', flush: true);
  }

  /// Every fix the GPS delivered, before any filtering. Lets us replay a
  /// real walk on the PC and tune filters against real data.
  Future<void> appendRaw(TrackPoint p) async {
    final f = _raw;
    if (f == null) return;
    await f.writeAsString('${jsonEncode(p.toJson())}\n',
        mode: FileMode.append);
  }

  Future<void> append(TrackPoint p) async {
    final f = _current;
    if (f == null) return;
    await f.writeAsString('${jsonEncode(p.toJson())}\n',
        mode: FileMode.append, flush: true);
  }

  Future<void> finish() async {
    final f = _current;
    if (f == null) return;
    await f.writeAsString('${jsonEncode({'end': true})}\n',
        mode: FileMode.append, flush: true);
    _current = null;
    _raw = null;
  }

  Future<StoredSession?> loadLatest() async {
    if (!await dir.exists()) return null;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.uri.pathSegments.last.startsWith('session_') &&
            f.path.endsWith('.jsonl'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) return null;
    final file = files.last;
    final points = <TrackPoint>[];
    var finished = false;
    for (final line in await file.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        final j = jsonDecode(line) as Map<String, Object?>;
        if (j['end'] == true) {
          finished = true;
        } else {
          points.add(TrackPoint.fromJson(j));
        }
      } on FormatException {
        // torn line from a kill mid-write: skip it
      }
    }
    return StoredSession(points, finished: finished, file: file);
  }

  /// Continue appending to an unfinished session after a restart.
  void resume(File file) {
    _current = file;
    _raw = File(file.path.replaceFirst('session_', 'raw_'));
  }
}
