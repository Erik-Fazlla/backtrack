import 'package:flutter/foundation.dart';

import '../app_services.dart';
import '../core/geo.dart';
import '../core/path_matcher.dart';
import 'path_source.dart';

/// The trail as it should be drawn: snapped onto mapped paths when the
/// "Snap to paths" setting is on and an offline map covers it, otherwise
/// exactly as recorded. Display only — saved points never change.
Future<List<TrackPoint>> displayTrail(
    AppServices services, List<TrackPoint> points) async {
  final on = services.settings?.snapToPaths ?? false;
  final region = services.maps?.active;
  if (!on || region == null || points.length < 2) return points;
  PathSource? src;
  try {
    src = await PathSource.open(region.path);
    final lines = await src.around(points);
    return snapToPaths(points, lines);
  } catch (e) {
    debugPrint('[snap] failed, showing recorded trail: $e');
    return points;
  } finally {
    await src?.close();
  }
}
