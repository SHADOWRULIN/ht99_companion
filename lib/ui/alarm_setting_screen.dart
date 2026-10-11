import 'package:flutter/material.dart';
import '../services/watch_ble_service.dart';
import '../models/telemetry_model.dart';

class AlarmSettingScreen extends StatefulWidget {
  final WatchBleService ble;

  const AlarmSettingScreen({super.key, required this.ble});

  @override
  State<AlarmSettingScreen> createState() => _AlarmSettingScreenState();
}

class _AlarmSettingScreenState extends State<AlarmSettingScreen> {
  int _selectedHour = 7;
  int _selectedMinute = 0;
  final List<bool> _days = [false, true, true, true, true, true, false];
  final List<String> _dayNames = [
    "SUN",
    "MON",
    "TUE",
    "WED",
    "THU",
    "FRI",
    "SAT"
  ];

  void _showAddAlarmModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text("cancel")),
                  const Text("Alarm setting",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () {
                      widget.ble.saveAlarm(WatchAlarm(
                        hour: _selectedHour,
                        minute: _selectedMinute,
                        days: List.from(_days),
                      ));
                      Navigator.pop(ctx);
                    },
                    child: const Text("save",
                        style: TextStyle(color: Color(0xFFF5BE53))),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DropdownButton<int>(
                    value: _selectedHour,
                    items: List.generate(
                        24,
                        (i) => DropdownMenuItem(
                            value: i,
                            child: Text("${i.toString().padLeft(2, '0')}h"))),
                    onChanged: (v) => setModal(() => _selectedHour = v ?? 0),
                  ),
                  const SizedBox(width: 20),
                  DropdownButton<int>(
                    value: _selectedMinute,
                    items: List.generate(
                        60,
                        (i) => DropdownMenuItem(
                            value: i,
                            child: Text("${i.toString().padLeft(2, '0')}m"))),
                    onChanged: (v) => setModal(() => _selectedMinute = v ?? 0),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text("period", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(7, (i) {
                  return FilterChip(
                    label: Text(_dayNames[i],
                        style: const TextStyle(fontSize: 10)),
                    selected: _days[i],
                    selectedColor: const Color(0xFFF5BE53),
                    onSelected: (val) => setModal(() => _days[i] = val),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Alarm setting"),
        actions: [
          IconButton(
              icon: const Icon(Icons.add), onPressed: _showAddAlarmModal),
        ],
      ),
      body: widget.ble.telemetry.alarms.isEmpty
          ? const Center(
              child: Text("No alarms set. Tap + to add.",
                  style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              itemCount: widget.ble.telemetry.alarms.length,
              itemBuilder: (ctx, i) {
                var a = widget.ble.telemetry.alarms[i];
                return SwitchListTile(
                  title: Text(
                      "${a.hour.toString().padLeft(2, '0')}:${a.minute.toString().padLeft(2, '0')}",
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  value: a.isEnabled,
                  onChanged: (v) {
                    setState(() => a.isEnabled = v);
                    widget.ble.saveAlarm(a);
                  },
                );
              },
            ),
    );
  }
}
