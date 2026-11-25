import 'package:flutter/foundation.dart';

import 'services/app_settings.dart';
import 'services/gps_monitor.dart';
import 'services/heading_service.dart';
import 'services/journey_repo.dart';
import 'services/location_service.dart';
import 'services/offline_maps.dart';
import 'services/recorder.dart';

/// Everything the screens need, created once in main().
class AppServices {
  AppServices({
    required this.recorder,
    required this.repo,
    this.location,
    this.settings,
    this.maps,
    this.gps,
    this.heading,
    this.showTiles = true,
  });

  final Recorder recorder;
  final JourneyRepo repo;

  /// Null in widget tests (no GPS, no permissions).
  final LocationService? location;
  final AppSettings? settings;
  final OfflineMaps? maps;

  /// GPS warm-up before Record (null in tests).
  final GpsMonitor? gps;

  /// Compass direction for the beam / follow arrow (null in tests).
  final HeadingService? heading;

  /// False in widget tests (no network).
  final bool showTiles;

  /// Bumped whenever journeys are added, renamed, recoloured or deleted,
  /// so the Library and Map tabs refresh.
  final journeysChanged = ValueNotifier<int>(0);
  void notifyJourneysChanged() => journeysChanged.value++;
}
