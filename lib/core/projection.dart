import 'dart:math' as math;
import 'dart:ui';

typedef LatLon = ({double lat, double lon});

const double _mPerDegLat = 111195.0;

/// Fits a trail into a screen box with north up and true proportions.
/// Local equirectangular projection: exact enough for walks of a few km.
class TrailProjection {
  TrailProjection._(this._centerLat, this._centerLon, this._cosLat,
      this.metresPerPixel, this._size);

  final double _centerLat;
  final double _centerLon;
  final double _cosLat;
  final double metresPerPixel;
  final Size _size;

  factory TrailProjection.fit(
    List<LatLon> pts,
    Size size, {
    double padding = 24,
    double minMetresAcross = 200,
  }) {
    assert(pts.isNotEmpty);
    var minLat = pts.first.lat, maxLat = minLat;
    var minLon = pts.first.lon, maxLon = minLon;
    for (final p in pts) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLon = math.min(minLon, p.lon);
      maxLon = math.max(maxLon, p.lon);
    }
    final cLat = (minLat + maxLat) / 2;
    final cLon = (minLon + maxLon) / 2;
    final cosLat = math.cos(cLat * math.pi / 180);
    final heightM = (maxLat - minLat) * _mPerDegLat;
    final widthM = (maxLon - minLon) * _mPerDegLat * cosLat;
    final availW = math.max(1.0, size.width - 2 * padding);
    final availH = math.max(1.0, size.height - 2 * padding);
    var mpp = math.max(widthM / availW, heightM / availH);
    final minMpp = minMetresAcross / math.min(availW, availH);
    mpp = math.max(mpp, minMpp);
    return TrailProjection._(cLat, cLon, cosLat, mpp, size);
  }

  Offset toScreen(double lat, double lon) {
    final xM = (lon - _centerLon) * _mPerDegLat * _cosLat;
    final yM = (lat - _centerLat) * _mPerDegLat;
    return Offset(
      _size.width / 2 + xM / metresPerPixel,
      _size.height / 2 - yM / metresPerPixel,
    );
  }
}
