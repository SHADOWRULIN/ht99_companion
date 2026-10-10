import 'package:flutter/material.dart';

class MyTab extends StatelessWidget {
  final ThemeMode currentTheme;
  final Function(ThemeMode) onThemeChange;
  final int stepGoal;
  final Function(int) onGoalChange;

  const MyTab({
    super.key,
    required this.currentTheme,
    required this.onThemeChange,
    required this.stepGoal,
    required this.onGoalChange,
  });

  void _showStepPicker(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Step Target",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: [6000, 8000, 10000, 12000, 15000].map((v) {
                return ChoiceChip(
                  label: Text("$v step"),
                  selected: stepGoal == v,
                  onSelected: (sel) {
                    if (sel) {
                      onGoalChange(v);
                      Navigator.pop(ctx);
                    }
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Center(
          child: CircleAvatar(
            radius: 36,
            backgroundColor: Color(0xFFFF5722),
            child: Text("HT",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 24),
        const Text("target settings", style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 10),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              ListTile(
                leading: const CircleAvatar(
                    backgroundColor: Color(0x22FF5722),
                    child:
                        Icon(Icons.directions_walk, color: Color(0xFFFF5722))),
                title: const Text("Step target"),
                subtitle: Text("$stepGoal step"),
                onTap: () => _showStepPicker(context),
              ),
              const Divider(height: 1, indent: 64),
              const ListTile(
                leading: CircleAvatar(
                    backgroundColor: Color(0x223F51B5),
                    child: Icon(Icons.bedtime, color: Colors.indigoAccent)),
                title: Text("Sleep target"),
                subtitle: Text("8 hour"),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text("more", style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 10),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.brightness_medium_rounded),
                title: const Text("Appearance Theme"),
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
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text("About us"),
                subtitle: Text("HT99 Companion Pro v2.0"),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
