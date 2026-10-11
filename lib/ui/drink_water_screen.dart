import 'package:flutter/material.dart';
import '../services/watch_ble_service.dart';

class DrinkWaterScreen extends StatefulWidget {
  final WatchBleService ble;

  const DrinkWaterScreen({super.key, required this.ble});

  @override
  State<DrinkWaterScreen> createState() => _DrinkWaterScreenState();
}

class _DrinkWaterScreenState extends State<DrinkWaterScreen> {
  final List<String> timeSlots = [
    "08:00",
    "09:00",
    "10:00",
    "11:00",
    "12:00",
    "14:00",
    "15:00",
    "16:00"
  ];
  final List<bool> slotToggles = List.filled(8, false);

  void _showIntervalPicker() {
    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Select Reminder Interval",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...[15, 30, 60].map((mins) => ListTile(
                  title: Text("every $mins minutes"),
                  selected:
                      widget.ble.telemetry.drinkWaterIntervalMinutes == mins,
                  onTap: () {
                    widget.ble.setDrinkWaterReminder(true, mins);
                    Navigator.pop(context);
                    setState(() {});
                  },
                )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Reminder to drink water")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                const Icon(Icons.water_drop_outlined,
                    color: Colors.blueAccent, size: 40),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Come and set a drink reminder for your health",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text("add time from here to set drinking reminder",
                          style: TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _showIntervalPicker,
                  child: Text(
                      "${widget.ble.telemetry.drinkWaterIntervalMinutes}m"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(timeSlots.length, (i) {
            return SwitchListTile(
              title: Text(timeSlots[i],
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              value: slotToggles[i],
              activeColor: const Color(0xFFFF5722),
              onChanged: (val) {
                setState(() => slotToggles[i] = val);
                widget.ble.setDrinkWaterReminder(
                    val, widget.ble.telemetry.drinkWaterIntervalMinutes);
              },
            );
          }),
        ],
      ),
    );
  }
}
