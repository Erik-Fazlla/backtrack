import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Look of the offline map.
enum MapStyle { light, dark }

/// Small persisted settings, stored as JSON next to the recordings.
class AppSettings extends ChangeNotifier {
  AppSettings(this.file);

  final File file;
  MapStyle _mapStyle = MapStyle.light;
  MapStyle get mapStyle => _mapStyle;

  /// Show trails pulled onto nearby mapped paths (display only).
  bool _snapToPaths = false;
  bool get snapToPaths => _snapToPaths;

  Future<void> load() async {
    try {
      if (!await file.exists()) return;
      final j = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      _mapStyle = MapStyle.values.firstWhere(
        (m) => m.name == j['mapStyle'],
        orElse: () => MapStyle.light,
      );
      _snapToPaths = j['snapToPaths'] == true;
    } on FormatException {
      // corrupt file: keep defaults
    }
  }

  Future<void> setMapStyle(MapStyle m) async {
    if (m == _mapStyle) return;
    _mapStyle = m;
    await _save();
  }

  Future<void> setSnapToPaths(bool v) async {
    if (v == _snapToPaths) return;
    _snapToPaths = v;
    await _save();
  }

  Future<void> _save() async {
    notifyListeners();
    await file.parent.create(recursive: true);
    await file.writeAsString(
        jsonEncode({
          'mapStyle': _mapStyle.name,
          'snapToPaths': _snapToPaths,
        }),
        flush: true);
  }
}
