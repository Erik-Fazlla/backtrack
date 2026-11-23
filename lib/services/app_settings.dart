import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Which positioning source to record with.
enum GpsMode {
  /// Raw satellite GPS only (Android GPS_PROVIDER).
  satellites,

  /// Google's fused provider: GPS + motion sensors (+ Wi-Fi/cell if on).
  fused,
}

/// Small persisted settings, stored as JSON next to the recordings.
class AppSettings extends ChangeNotifier {
  AppSettings(this.file);

  final File file;
  GpsMode _gpsMode = GpsMode.satellites;
  GpsMode get gpsMode => _gpsMode;

  Future<void> load() async {
    try {
      if (!await file.exists()) return;
      final j = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      _gpsMode = GpsMode.values.firstWhere(
        (m) => m.name == j['gpsMode'],
        orElse: () => GpsMode.satellites,
      );
    } on FormatException {
      // corrupt file: keep defaults
    }
  }

  Future<void> setGpsMode(GpsMode m) async {
    if (m == _gpsMode) return;
    _gpsMode = m;
    notifyListeners();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({'gpsMode': m.name}), flush: true);
  }
}
