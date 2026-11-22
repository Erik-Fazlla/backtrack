import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'features/record/record_screen.dart';
import 'services/location_service.dart';
import 'services/recorder.dart';
import 'services/track_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final docs = await getApplicationDocumentsDirectory();
  final location = LocationService();
  final recorder = Recorder(
    store: TrackStore(Directory('${docs.path}/sessions')),
    positions: location.positions,
  );
  // If the app was killed mid-recording, pick the trail back up.
  await recorder.restore();
  runApp(BacktrackApp(recorder: recorder, location: location));
}

class BacktrackApp extends StatelessWidget {
  const BacktrackApp({
    super.key,
    required this.recorder,
    this.location,
    this.showTiles = true,
  });

  final Recorder recorder;
  final LocationService? location;
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
          recorder: recorder, location: location, showTiles: showTiles),
    );
  }
}
