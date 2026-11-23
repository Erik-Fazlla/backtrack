import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/elevation.dart';

/// Distance (km) vs altitude (m). Shows the climbs and descents of a trail.
class ElevationChart extends StatelessWidget {
  const ElevationChart({super.key, required this.profile, required this.color});
  final List<ProfilePoint> profile;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (profile.length < 2) {
      return const SizedBox(
        height: 80,
        child: Center(child: Text('No altitude data for this journey.')),
      );
    }
    final t = Theme.of(context).textTheme;
    var minA = profile.first.altitudeM, maxA = minA;
    for (final p in profile) {
      if (p.altitudeM < minA) minA = p.altitudeM;
      if (p.altitudeM > maxA) maxA = p.altitudeM;
    }
    // Keep at least 20 m of vertical range so flat walks look flat.
    final pad = ((20 - (maxA - minA)) / 2).clamp(2, 20).toDouble();
    final km = profile.last.distanceM >= 1000;
    return SizedBox(
      height: 170,
      child: LineChart(
        LineChartData(
          minY: minA - pad,
          maxY: maxA + pad,
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${s.y.toStringAsFixed(0)} m\n'
                    '${km ? '${s.x.toStringAsFixed(2)} km' : '${s.x.toStringAsFixed(0)} m'}',
                    t.labelMedium!.copyWith(color: Colors.white),
                  ),
              ],
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (v, meta) =>
                    Text('${v.toStringAsFixed(0)} m', style: t.labelSmall),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, meta) => Text(
                    km ? '${v.toStringAsFixed(1)} km' : '${v.toStringAsFixed(0)} m',
                    style: t.labelSmall),
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (final p in profile)
                  FlSpot(km ? p.distanceM / 1000 : p.distanceM, p.altitudeM),
              ],
              isCurved: true,
              color: color,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
