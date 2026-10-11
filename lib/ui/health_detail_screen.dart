import 'package:flutter/material.dart';
import '../services/watch_ble_service.dart';

class HealthDetailScreen extends StatelessWidget {
  final String type;
  final WatchBleService ble;

  const HealthDetailScreen({super.key, required this.type, required this.ble});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(type),
        actions: [
          if (type == "HeartRate" && ble.isConnected)
            IconButton(
              icon: const Icon(Icons.play_arrow_rounded,
                  color: Color(0xFFF5BE53)),
              onPressed: () => ble.measureHeartRateLive(),
              tooltip: "Measure Now",
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: type == "HeartRate"
            ? _buildHeartRateLayout()
            : _buildGenericLayout(),
      ),
    );
  }

  Widget _buildHeartRateLayout() {
    int current = ble.telemetry.heartRate;
    int max = ble.telemetry.hrHistory.isEmpty
        ? current
        : ble.telemetry.hrHistory
            .map((e) => e.bpm)
            .reduce((a, b) => a > b ? a : b);
    int min = ble.telemetry.hrHistory.isEmpty
        ? current
        : ble.telemetry.hrHistory
            .map((e) => e.bpm)
            .reduce((a, b) => a < b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text("average heart rate", style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 6),
        Text("$current times / minutes",
            style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF4757))),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(
              children: [
                Text("$max bpm",
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.pinkAccent)),
                const Text("maximum heart rate",
                    style: TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
            Column(
              children: [
                Text("$min bpm",
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.purpleAccent)),
                const Text("minimum heart rate",
                    style: TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 30),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text("heart rate record",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ble.telemetry.hrHistory.isEmpty
              ? const Center(
                  child: Text("no data temporarily",
                      style: TextStyle(color: Colors.grey)))
              : ListView.separated(
                  itemCount: ble.telemetry.hrHistory.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    var r = ble.telemetry.hrHistory[i];
                    return ListTile(
                      leading: const Icon(Icons.circle,
                          color: Color(0xFFFF4757), size: 10),
                      title: Text("${r.bpm} bpm",
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: Text(r.time,
                          style: const TextStyle(color: Colors.grey)),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildGenericLayout() {
    return Column(
      children: [
        const SizedBox(height: 40),
        Icon(
          type == "BP"
              ? Icons.water_drop
              : (type == "Thermometer"
                  ? Icons.thermostat
                  : Icons.nightlight_round),
          size: 64,
          color: const Color(0xFFF5BE53),
        ),
        const SizedBox(height: 20),
        Text(
          type == "BP"
              ? "${ble.telemetry.systolicBp}/${ble.telemetry.diastolicBp} mmHg"
              : (type == "Thermometer"
                  ? "${ble.telemetry.bodyTemp} °C"
                  : "${ble.telemetry.sleepHours} h"),
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 30),
        const Text(
            "Measurement records will sync continuously while worn on your wrist.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey)),
      ],
    );
  }
}
