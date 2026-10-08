import 'package:flutter/material.dart';
import '../services/watch_ble_service.dart';

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
            const Text("Activity",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.sync_rounded),
              onPressed:
                  ble.targetDevice != null ? () => ble.syncPhoneTime() : null,
              tooltip: "Sync Clock",
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
              const Text("Today's Steps",
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
                      color: const Color(0xFFFF5722),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        "${ble.telemetry.steps}",
                        style: const TextStyle(
                            fontSize: 36, fontWeight: FontWeight.bold),
                      ),
                      Text("Goal: $stepGoal",
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
                  _stat("${(progress * 100).toInt()}%", "Progress"),
                  _stat("${ble.telemetry.calories}", "kcal"),
                  _stat("${ble.telemetry.distanceKm.toStringAsFixed(2)}", "km"),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _infoTile(
                context,
                Icons.favorite_rounded,
                Colors.redAccent,
                "Heart Rate",
                ble.telemetry.heartRate > 0
                    ? "${ble.telemetry.heartRate} BPM"
                    : "-- BPM",
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _infoTile(
                context,
                Icons.battery_charging_full_rounded,
                Colors.tealAccent,
                "Battery",
                "${ble.telemetry.batteryLevel}%",
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _infoTile(BuildContext context, IconData icon, Color color,
      String title, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
