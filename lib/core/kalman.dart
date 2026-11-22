import 'geo.dart';

/// Simple Kalman filter for GPS positions (constant-position model).
///
/// Each fix is blended with the current estimate, weighted by its reported
/// accuracy. Between fixes the uncertainty grows by how far a person could
/// have moved ([processNoiseMps]). Result: jitter while walking is smoothed
/// away, but real turns are followed within a few metres.
class PositionSmoother {
  PositionSmoother({this.processNoiseMps = 3});

  final double processNoiseMps;

  double? _lat;
  double? _lon;
  double _varianceM2 = 0;
  DateTime? _time;

  TrackPoint update(TrackPoint raw) {
    final acc = raw.accuracyM < 1 ? 1.0 : raw.accuracyM;
    if (_lat == null) {
      _lat = raw.lat;
      _lon = raw.lon;
      _varianceM2 = acc * acc;
      _time = raw.time;
      return raw;
    }
    final dt = raw.time.difference(_time!).inMilliseconds / 1000;
    if (dt > 0) {
      _varianceM2 += dt * processNoiseMps * processNoiseMps;
      _time = raw.time;
    }
    final k = _varianceM2 / (_varianceM2 + acc * acc);
    _lat = _lat! + k * (raw.lat - _lat!);
    _lon = _lon! + k * (raw.lon - _lon!);
    _varianceM2 = (1 - k) * _varianceM2;
    return TrackPoint(
      lat: _lat!,
      lon: _lon!,
      accuracyM: raw.accuracyM,
      altitudeM: raw.altitudeM,
      time: raw.time,
    );
  }

  void reset() {
    _lat = null;
    _lon = null;
    _time = null;
    _varianceM2 = 0;
  }
}
