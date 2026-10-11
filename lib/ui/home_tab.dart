import 'package:flutter/material.dart';
import '../services/watch_ble_service.dart';
import 'health_detail_screen.dart';

class HomeTab extends StatelessWidget {
  final WatchBleService ble;
  final int stepGoal;

  const HomeTab({super.key, required this.ble, required this.stepGoal});

  @override
  Widget build(BuildContext context) {
    double progress = (ble.telemetry.steps / stepGoal).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Home",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFFF5BE53)),
              onPressed:
                  ble.isConnected ? () => ble.queryAllHealthData() : null,
              tooltip: "Refresh Health Data",
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              const Text("today's steps",
                  style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 16),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 170,
                    height: 170,
                    child: CircularProgressIndicator(
                      value: progress == 0 ? 0.05 : progress,
                      strokeWidth: 14,
                      backgroundColor: Colors.white12,
                      color: const Color(0xFFF5BE53),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    children: [
                      Text("${ble.telemetry.steps}",
                          style: const TextStyle(
                              fontSize: 36, fontWeight: FontWeight.bold)),
                      Text("goal: $stepGoal",
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _stat("${(progress * 100).toInt()}%", "Percent"),
                  _stat("${ble.telemetry.calories}", "kcal"),
                  _stat("${ble.telemetry.distanceKm.toStringAsFixed(2)}", "km"),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.35,
          children: [
            _card(
              context,
              icon: Icons.nightlight_round,
              color: Colors.indigoAccent,
              title: "Sleep",
              value: ble.telemetry.sleepHours > 0
                  ? "${ble.telemetry.sleepHours} h"
                  : "--",
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          HealthDetailScreen(type: "Sleep", ble: ble))),
            ),
            _card(
              context,
              icon: Icons.favorite_rounded,
              color: const Color(0xFFFF4757),
              title: "HeartRate",
              value: ble.telemetry.heartRate > 0
                  ? "${ble.telemetry.heartRate} bpm"
                  : "-- times/minute",
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          HealthDetailScreen(type: "HeartRate", ble: ble))),
            ),
            _card(
              context,
              icon: Icons.water_drop_rounded,
              color: Colors.redAccent,
              title: "BP",
              value: ble.telemetry.systolicBp > 0
                  ? "${ble.telemetry.systolicBp}/${ble.telemetry.diastolicBp} mmHg"
                  : "-- mmHg",
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          HealthDetailScreen(type: "BP", ble: ble))),
            ),
            _card(
              context,
              icon: Icons.bubble_chart_rounded,
              color: Colors.amber,
              title: "Immunity",
              value: ble.telemetry.immunity > 0
                  ? "${ble.telemetry.immunity} %"
                  : "-- %",
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          HealthDetailScreen(type: "Immunity", ble: ble))),
            ),
            _card(
              context,
              icon: Icons.thermostat_rounded,
              color: Colors.tealAccent,
              title: "Thermometer",
              value: ble.telemetry.bodyTemp > 0
                  ? "${ble.telemetry.bodyTemp} °C"
                  : "-- °C",
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          HealthDetailScreen(type: "Thermometer", ble: ble))),
            ),
            _card(
              context,
              icon: Icons.battery_charging_full_rounded,
              color: Colors.cyanAccent,
              title: "Battery",
              value: ble.telemetry.batteryLevel >= 0
                  ? "${ble.telemetry.batteryLevel} %"
                  : "-- %",
              onTap: null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _stat(String v, String l) => Column(children: [
        Text(v,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(l, style: const TextStyle(fontSize: 11, color: Colors.grey))
      ]);

  Widget _card(BuildContext ctx,
      {required IconData icon,
      required Color color,
      required String title,
      required String value,
      VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const Spacer(),
            Text(title,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(value,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
