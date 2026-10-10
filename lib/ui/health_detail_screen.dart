import 'package:flutter/material.dart';
import '../services/watch_ble_service.dart';

class HealthDetailScreen extends StatelessWidget {
  final String type;
  final WatchBleService ble;

  const HealthDetailScreen({super.key, required this.type, required this.ble});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(type)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            if (type == "HeartRate") _buildHeartRateView(),
            if (type == "BP") _buildBpView(),
            if (type == "Thermometer") _buildThermometerView(),
            if (type == "Sleep") _buildSleepView(),
            if (type == "Immunity") _buildImmunityView(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeartRateView() {
    return Column(
      children: [
        const Text("average heart rate", style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 6),
        Text("${ble.telemetry.heartRate} bpm",
            style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF4757))),
        const SizedBox(height: 30),
        Container(
          height: 150,
          decoration: BoxDecoration(
              color: Colors.white10, borderRadius: BorderRadius.circular(16)),
          child: const Center(
              child: Text("Heart Rate Record Chart",
                  style: TextStyle(color: Colors.grey))),
        ),
      ],
    );
  }

  Widget _buildBpView() {
    return Column(
      children: [
        const Icon(Icons.water_drop_rounded, size: 64, color: Colors.redAccent),
        const SizedBox(height: 16),
        Text("${ble.telemetry.systolicBp} / ${ble.telemetry.diastolicBp}",
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
        const Text("systolic / diastolic (mmHg)",
            style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 30),
        const Text("blood pressure measurement record",
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(
            ble.telemetry.systolicBp > 0
                ? "Normal Range"
                : "no data temporarily",
            style: const TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _buildThermometerView() {
    return Column(
      children: [
        const Text("latest body temperature",
            style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 6),
        Text("${ble.telemetry.bodyTemp} °C",
            style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.tealAccent)),
        const SizedBox(height: 24),
        Container(
          height: 14,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            gradient: const LinearGradient(colors: [
              Colors.blue,
              Colors.green,
              Colors.yellow,
              Colors.orange,
              Colors.red
            ]),
          ),
        ),
        const SizedBox(height: 8),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("hypothermia",
                style: TextStyle(fontSize: 10, color: Colors.grey)),
            Text("normal", style: TextStyle(fontSize: 10, color: Colors.grey)),
            Text("low fever",
                style: TextStyle(fontSize: 10, color: Colors.grey)),
            Text("high heat",
                style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ],
    );
  }

  Widget _buildSleepView() {
    return Column(
      children: [
        const Text("total sleep time", style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 6),
        Text("${ble.telemetry.sleepHours} hours",
            style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.indigoAccent)),
        const SizedBox(height: 30),
        const Text("sleep record",
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(
            ble.telemetry.sleepHours > 0
                ? "Normal Sleep Cycle"
                : "no data temporarily",
            style: const TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _buildImmunityView() {
    return Column(
      children: [
        const Text("immunity index", style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 6),
        Text("${ble.telemetry.immunity} %",
            style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.amber)),
      ],
    );
  }
}
