import 'package:flutter/material.dart';

String formatDistance(double m) => m < 1000
    ? '${m.toStringAsFixed(0)} m'
    : '${(m / 1000).toStringAsFixed(m < 10000 ? 2 : 1)} km';

String formatDuration(int seconds) {
  final d = Duration(seconds: seconds);
  final h = d.inHours;
  final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '${d.inMinutes}:$ss';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatDate(DateTime utc) {
  final t = utc.toLocal();
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '${t.day} ${_months[t.month - 1]} ${t.year} · $hh:$mm';
}

/// Colour presets for categories: readable on both light and dark maps.
const categoryPalette = <int>[
  0xFFFF6B00, // orange
  0xFF2E9E4F, // green
  0xFF1E6FE8, // blue
  0xFF8E44AD, // purple
  0xFFE53935, // red
  0xFF00A3A3, // teal
  0xFFD4A000, // amber
  0xFFD81B87, // pink
  0xFF6D4C41, // brown
  0xFF7F8C8D, // grey
];

Color colorOf(int argb) => Color(argb);
