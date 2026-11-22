import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/geo.dart';

enum LocationReadiness { ready, serviceOff, denied, deniedForever }

/// Talks to the phone's GPS. Works with no internet: Android's fused
/// provider falls back to raw satellite GPS when there is no network.
class LocationService {
  /// Ask for everything recording needs. Returns what is still missing.
  Future<LocationReadiness> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationReadiness.serviceOff;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      return LocationReadiness.deniedForever;
    }
    if (perm == LocationPermission.denied) return LocationReadiness.denied;

    if (Platform.isAndroid) {
      // Android 13+: without this the "Recording" notification is hidden,
      // but the foreground service still runs.
      await Permission.notification.request();
    }
    return LocationReadiness.ready;
  }

  /// Battery optimisation can kill tracking on Xiaomi/Samsung etc.
  Future<bool> isBatteryOptimizationIgnored() =>
      Permission.ignoreBatteryOptimizations.isGranted;

  Future<void> requestIgnoreBatteryOptimization() =>
      Permission.ignoreBatteryOptimizations.request();

  Future<void> openAppSettings() => Geolocator.openAppSettings();
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  /// Continuous fixes. On Android this runs inside a foreground service
  /// (persistent notification), so it keeps going with the screen off.
  Stream<TrackPoint> positions({int distanceFilterM = 5}) {
    final LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: distanceFilterM,
            intervalDuration: const Duration(seconds: 2),
            useMSLAltitude: true,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Backtrack is recording',
              notificationText: 'Your trail is being saved, even offline.',
              notificationChannelName: 'Trail recording',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: distanceFilterM,
          );

    return Geolocator.getPositionStream(locationSettings: settings).map(
      (pos) => TrackPoint(
        lat: pos.latitude,
        lon: pos.longitude,
        accuracyM: pos.accuracy,
        altitudeM: pos.altitude == 0 ? null : pos.altitude,
        time: pos.timestamp.toUtc(),
      ),
    );
  }
}
