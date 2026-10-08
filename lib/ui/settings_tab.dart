import 'package:flutter/material.dart';

class SettingsTab extends StatelessWidget {
  final ThemeMode currentTheme;
  final Function(ThemeMode) onThemeChange;
  final int stepGoal;
  final Function(int) onGoalChange;

  const SettingsTab({
    super.key,
    required this.currentTheme,
    required this.onThemeChange,
    required this.stepGoal,
    required this.onGoalChange,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text("Settings",
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.brightness_medium_rounded),
                title: const Text("Appearance Theme"),
                subtitle: Text(currentTheme == ThemeMode.dark
                    ? "Dark Mode"
                    : "Light Mode"),
                trailing: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.light, icon: Icon(Icons.light_mode)),
                    ButtonSegment(
                        value: ThemeMode.dark, icon: Icon(Icons.dark_mode)),
                  ],
                  selected: {currentTheme},
                  onSelectionChanged: (set) => onThemeChange(set.first),
                ),
              ),
              const Divider(height: 1, indent: 64),
              ListTile(
                leading: const Icon(Icons.flag_rounded),
                title: const Text("Daily Step Target"),
                trailing: DropdownButton<int>(
                  value: stepGoal,
                  items: [5000, 8000, 10000, 15000]
                      .map((v) => DropdownMenuItem(value: v, child: Text("$v")))
                      .toList(),
                  onChanged: (v) => onGoalChange(v ?? 10000),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: const Column(
            children: [
              ListTile(
                leading: Icon(Icons.memory_rounded),
                title: Text("Platform"),
                subtitle: Text("MediaTek MTK2502C (320x385 IPS)"),
              ),
              Divider(height: 1, indent: 64),
              ListTile(
                leading: Icon(Icons.bluetooth_rounded),
                title: Text("BLE Target MAC"),
                subtitle: Text("F9:47:B2:F6:EC:7C"),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
