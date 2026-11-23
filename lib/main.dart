import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app_services.dart';
import 'features/journeys/journeys_map_screen.dart';
import 'features/journeys/library_screen.dart';
import 'features/record/record_screen.dart';
import 'services/app_settings.dart';
import 'services/journey_repo.dart';
import 'services/location_service.dart';
import 'services/offline_maps.dart';
import 'services/recorder.dart';
import 'services/track_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-edge: draw behind the status and navigation bars, which stay
  // transparent (no white strip under the app). Widgets keep their content
  // clear of the bars via SafeArea / NavigationBar insets.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  ));
  // App-specific external storage (Android/data/<app>/files): private to the
  // app on the phone, but reachable from the PC (Android Studio Device
  // Explorer / adb) for GPS logs, maps and database backups.
  final base = await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();
  final settings = AppSettings(File('${base.path}/settings.json'));
  await settings.load();
  final maps = OfflineMaps(Directory('${base.path}/maps'));
  await maps.scan();
  final repo = await JourneyRepo.open('${base.path}/journeys.db');
  final location = LocationService();
  final recorder = Recorder(
    store: TrackStore(Directory('${base.path}/sessions')),
    // Satellites only: on real walks Google/fused location reported ~0 m/s
    // while walking and was no more accurate (see docs/SPEC.md).
    positions: location.positions,
    sessionMeta: () => {
      'gpsMode': 'satellites',
      'app': 'backtrack-v0.1',
    },
  );
  // If the app was killed mid-recording, pick the trail back up.
  await recorder.restore();
  final last = recorder.points.isEmpty ? null : recorder.points.last;
  await maps.useFor(last?.lat, last?.lon);
  runApp(BacktrackApp(
    services: AppServices(
      recorder: recorder,
      repo: repo,
      location: location,
      settings: settings,
      maps: maps,
    ),
  ));
}

class BacktrackApp extends StatelessWidget {
  const BacktrackApp({super.key, required this.services});
  final AppServices services;

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
      home: AppShell(services: services),
    );
  }
}

/// Record · Library · Map tabs. Tabs stay alive so a recording keeps its
/// screen state while you browse.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.services});
  final AppServices services;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          RecordScreen(
            recorder: s.recorder,
            location: s.location,
            settings: s.settings,
            maps: s.maps,
            services: s,
            showTiles: s.showTiles,
          ),
          LibraryScreen(services: s),
          JourneysMapScreen(services: s),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.fiber_manual_record_outlined),
              selectedIcon: Icon(Icons.fiber_manual_record),
              label: 'Record'),
          NavigationDestination(
              icon: Icon(Icons.list_alt_outlined),
              selectedIcon: Icon(Icons.list_alt),
              label: 'Library'),
          NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Map'),
        ],
      ),
    );
  }
}
