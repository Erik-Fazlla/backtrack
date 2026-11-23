import 'dart:math' as math;

import 'geo.dart';

/// A road or footpath from the map, as (lat, lon) points.
class PathLine {
  const PathLine(this.points);
  final List<(double, double)> points;
}

/// Pulls a recorded trail onto nearby roads/paths for display, when the
/// trail clearly runs along one (within [maxDistM], roughly the same
/// direction). Where no path fits — you really walked off-trail — the
/// recorded points are kept exactly. Never changes what is saved.
///
/// Method: Viterbi over, per trail point, "on path line k at the nearest
/// spot" candidates plus one "off path" state. Scores favour small
/// distance, matching direction and staying on the same line; switching
/// lines is only cheap where the lines meet (crossroads).
List<TrackPoint> snapToPaths(
  List<TrackPoint> trail,
  List<PathLine> paths, {
  double maxDistM = 20,
  double sigmaM = 8,
  double maxAngleDeg = 40,
}) {
  if (trail.length < 2 || paths.isEmpty) return List.of(trail);

  // Local flat projection (metres) around the first point.
  final lat0 = trail.first.lat, lon0 = trail.first.lon;
  final cos0 = math.cos(lat0 * math.pi / 180);
  const m = 111195.0;
  (double, double) xy(double lat, double lon) =>
      ((lon - lon0) * m * cos0, (lat - lat0) * m);
  (double, double) toLatLon(double x, double y) =>
      (lat0 + y / m, lon0 + x / (m * cos0));

  final pts = [for (final p in trail) xy(p.lat, p.lon)];
  final lines = [
    for (final l in paths) [for (final (la, lo) in l.points) xy(la, lo)],
  ];

  // Direction of travel at each point (unit vector), from +-2 neighbours.
  final dirs = <(double, double)?>[];
  for (var i = 0; i < pts.length; i++) {
    final a = pts[math.max(0, i - 2)], b = pts[math.min(pts.length - 1, i + 2)];
    final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
    final len = math.sqrt(dx * dx + dy * dy);
    dirs.add(len < 3 ? null : (dx / len, dy / len));
  }

  // Candidates per point: best projection on each nearby line.
  final cands = <List<_Cand>>[];
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i];
    final list = <_Cand>[];
    for (var k = 0; k < lines.length; k++) {
      final l = lines[k];
      _Cand? best;
      for (var s = 0; s < l.length - 1; s++) {
        final a = l[s], b = l[s + 1];
        final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
        final len2 = dx * dx + dy * dy;
        if (len2 == 0) continue;
        var t = ((p.$1 - a.$1) * dx + (p.$2 - a.$2) * dy) / len2;
        t = t.clamp(0.0, 1.0);
        final qx = a.$1 + t * dx, qy = a.$2 + t * dy;
        final d = math.sqrt(math.pow(p.$1 - qx, 2) + math.pow(p.$2 - qy, 2));
        if (d > maxDistM) continue;
        // Angle between travel direction and the segment (undirected).
        var angle = 0.0;
        final dir = dirs[i];
        if (dir != null) {
          final len = math.sqrt(len2);
          final dot = ((dir.$1 * dx + dir.$2 * dy) / len).abs().clamp(0.0, 1.0);
          angle = math.acos(dot) * 180 / math.pi;
        }
        if (angle > maxAngleDeg) continue;
        final score = -(d * d) / (2 * sigmaM * sigmaM) -
            math.pow(angle / 25, 2).toDouble();
        if (best == null || score > best.score) {
          best = _Cand(k, qx, qy, d, score);
        }
      }
      if (best != null) list.add(best);
    }
    list.sort((a, b) => b.score.compareTo(a.score));
    cands.add(list.take(5).toList());
  }

  // "Off path" state: as good as being maxDist*0.75 away from a path,
  // so only clearly-fitting stretches get snapped.
  final offScore = -math.pow(maxDistM * 0.75, 2) / (2 * sigmaM * sigmaM);
  const switchOnOff = -3.0; // entering / leaving a path
  const switchLine = -4.0; // changing line far from where they meet

  // Viterbi. State index: 0 = off path, 1.. = candidate (idx-1).
  final score = <List<double>>[];
  final back = <List<int>>[];
  for (var i = 0; i < pts.length; i++) {
    final cs = cands[i];
    final cur = List<double>.filled(cs.length + 1, 0);
    final bp = List<int>.filled(cs.length + 1, 0);
    if (i == 0) {
      cur[0] = offScore;
      for (var c = 0; c < cs.length; c++) {
        cur[c + 1] = cs[c].score;
      }
    } else {
      final prev = score[i - 1];
      final pcs = cands[i - 1];
      double trans(int from, int to) {
        if (from == 0 && to == 0) return 0;
        if (from == 0 || to == 0) return switchOnOff;
        final a = pcs[from - 1], b = cs[to - 1];
        if (a.line == b.line) {
          // Moving along the line should match moving along the trail.
          final along = math.sqrt(
              math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
          final walked = math.sqrt(math.pow(pts[i].$1 - pts[i - 1].$1, 2) +
              math.pow(pts[i].$2 - pts[i - 1].$2, 2));
          final diff = (along - walked).abs();
          return -diff / 10;
        }
        // Different line: cheap only if the snapped spots are close
        // (the lines meet here).
        final gap = math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
        final walked = math.sqrt(math.pow(pts[i].$1 - pts[i - 1].$1, 2) +
            math.pow(pts[i].$2 - pts[i - 1].$2, 2));
        return gap <= walked + 6 ? -1.0 : switchLine - gap / 10;
      }

      for (var to = 0; to <= cs.length; to++) {
        final emit = to == 0 ? offScore : cs[to - 1].score;
        var best = double.negativeInfinity;
        var arg = 0;
        for (var from = 0; from < prev.length; from++) {
          final v = prev[from] + trans(from, to);
          if (v > best) {
            best = v;
            arg = from;
          }
        }
        cur[to] = best + emit;
        bp[to] = arg;
      }
    }
    score.add(cur);
    back.add(bp);
  }

  // Backtrack.
  final states = List<int>.filled(pts.length, 0);
  var s = 0;
  var bestEnd = double.negativeInfinity;
  for (var k = 0; k < score.last.length; k++) {
    if (score.last[k] > bestEnd) {
      bestEnd = score.last[k];
      s = k;
    }
  }
  for (var i = pts.length - 1; i >= 0; i--) {
    states[i] = s;
    s = back[i][s];
  }

  return [
    for (var i = 0; i < trail.length; i++)
      if (states[i] == 0)
        trail[i]
      else
        _moved(trail[i], toLatLon(cands[i][states[i] - 1].x,
            cands[i][states[i] - 1].y)),
  ];
}

TrackPoint _moved(TrackPoint p, (double, double) ll) => TrackPoint(
      lat: ll.$1,
      lon: ll.$2,
      accuracyM: p.accuracyM,
      altitudeM: p.altitudeM,
      speedMps: p.speedMps,
      headingDeg: p.headingDeg,
      time: p.time,
    );

class _Cand {
  _Cand(this.line, this.x, this.y, this.distM, this.score);
  final int line;
  final double x, y, distM, score;
}
