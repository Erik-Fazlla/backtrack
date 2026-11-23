import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'features/record/record_screen.dart';
import 'services/app_settings.dart';
import 'services/location_service.dart';
import 'services/recorder.dart';
import 'services/track_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // App-specific external storage (Android/data/<app>/files): private to the
  // app on the phone, but reachable from the PC (Android Studio Device
  // Explorer / adb) so real GPS logs can be replayed and tuned.
  final base = await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();
  final settings = AppSettings(File('${base.path}/settings.json'));
  await settings.load();
  final location = LocationService();
  final recorder = Recorder(
    store: TrackStore(Directory('${base.path}/sessions')),
    positions: () =>
        location.positions(fused: settings.gpsMode == GpsMode.fused),
    sessionMeta: () => {
      'gpsMode': settings.gpsMode.name,
      'app': 'backtrack-m0',
    },
  );
  // If the app was killed mid-recording, pick the trail back up.
  await recorder.restore();
  runApp(BacktrackApp(
      recorder: recorder, location: location, settings: settings));
}

class BacktrackApp extends StatelessWidget {
  const BacktrackApp({
    super.key,
    required this.recorder,
    this.location,
    this.settings,
    this.showTiles = true,
  });

  final Recorder recorder;
  final LocationService? location;
  final AppSettings? settings;
  final bool showTiles;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFFF6B00);
    return MaterialApp(
      title: 'Backtrack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: seed,
          brightness: Brightness.dark,
          useMaterial3: true),
      home: RecordScreen(
        recorder: recorder,
        location: location,
        settings: settings,
        showTiles: showTiles,
      ),
    );
  }
}
