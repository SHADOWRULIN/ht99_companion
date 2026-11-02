import 'package:flutter/material.dart';
import '../services/watch_ble_service.dart';

class SyncSettingsScreen extends StatefulWidget {
  final WatchBleService ble;

  const SyncSettingsScreen({super.key, required this.ble});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  WatchBleService get ble => widget.ble;

  late bool _use24 = ble.is24Hour;
  bool _sedentary = false;
  double _sedMin = 60;

  double _temp = 28;
  double _low = 22;
  double _high = 33;
  int _cond = 0;

  final TextEditingController _city = TextEditingController(text: "Karachi");
  final TextEditingController _goal = TextEditingController();
  final TextEditingController _height = TextEditingController();
  final TextEditingController _weight = TextEditingController();
  bool _male = true;

  @override
  void initState() {
    super.initState();
    _goal.text = ble.stepGoal.toString();
    _height.text = ble.heightCm.toString();
    _weight.text = ble.weightKg.toString();
    _male = ble.male;
  }

  @override
  void dispose() {
    _city.dispose();
    _goal.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final bool connected = ble.isConnected;

    return Scaffold(
      appBar: AppBar(title: const Text("Sync & Settings")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 1. Time & Format Card
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Clock & Time Format",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Use 24-Hour Format"),
                    subtitle:
                        Text(_use24 ? "24-Hour (Military)" : "12-Hour (AM/PM)"),
                    value: _use24,
                    activeThumbColor: const Color(0xFFF5BE53),
                    onChanged: connected
                        ? (val) {
                            setState(() => _use24 = val);
                            ble.setTimeFormat(is24h: val);
                            _toast("Time format synced to watch");
                          }
                        : null,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: connected
                          ? () {
                              ble.syncTime(use24Hour: _use24);
                              _toast("Phone time synced to watch!");
                            }
                          : null,
                      icon: const Icon(Icons.access_time_filled_rounded),
                      label: const Text("Sync Phone Time Now"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF5BE53),
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 2. Weather Forecast Push Card
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Weather Push",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _city,
                    decoration: const InputDecoration(
                      labelText: "City Name",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _cond,
                    decoration: const InputDecoration(
                      labelText: "Condition",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text("Sunny / Clear")),
                      DropdownMenuItem(value: 1, child: Text("Cloudy")),
                      DropdownMenuItem(value: 2, child: Text("Rain")),
                      DropdownMenuItem(value: 3, child: Text("Snow")),
                    ],
                    onChanged: (v) => setState(() => _cond = v ?? 0),
                  ),
                  const SizedBox(height: 12),
                  Text(
                      "Current: ${_temp.round()}°C  (Low: ${_low.round()}°C / High: ${_high.round()}°C)"),
                  Slider(
                    value: _temp,
                    min: -10,
                    max: 50,
                    activeColor: const Color(0xFFF5BE53),
                    onChanged: (v) => setState(() => _temp = v),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Text("Low: ${_low.round()}°C",
                                style: const TextStyle(fontSize: 12)),
                            Slider(
                              value: _low,
                              min: -10,
                              max: 45,
                              onChanged: (v) => setState(() => _low = v),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text("High: ${_high.round()}°C",
                                style: const TextStyle(fontSize: 12)),
                            Slider(
                              value: _high,
                              min: 0,
                              max: 55,
                              onChanged: (v) => setState(() => _high = v),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: connected
                          ? () {
                              ble.pushWeather(
                                _temp.round(),
                                _cond,
                                _high.round(),
                                _low.round(),
                                city: _city.text,
                              );
                              _toast("Weather forecast sent to watch!");
                            }
                          : null,
                      icon: const Icon(Icons.wb_sunny_rounded),
                      label: const Text("Push Weather to Watch"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF5BE53),
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 3. User Body Profile & Step Goal Card
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "User Profile (Calorie & Stride Calibration)",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _goal,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Step Goal",
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _height,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Height (cm)",
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _weight,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Weight (kg)",
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Gender"),
                    subtitle: Text(_male ? "Male" : "Female"),
                    value: _male,
                    activeThumbColor: const Color(0xFFF5BE53),
                    onChanged: (v) => setState(() => _male = v),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: connected
                          ? () {
                              ble.syncUserInfo(
                                goal: int.tryParse(_goal.text) ?? 10000,
                                height: int.tryParse(_height.text) ?? 170,
                                weight: int.tryParse(_weight.text) ?? 65,
                                isMale: _male,
                              );
                              _toast("User profile synced to watch!");
                            }
                          : null,
                      icon: const Icon(Icons.person_pin_rounded),
                      label: const Text("Sync Profile to Watch"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF5BE53),
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 4. Sedentary Reminder Card
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Long-Sit (Sedentary) Reminder",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Enable Sedentary Alert"),
                    subtitle: Text(
                        "Every ${_sedMin.round()} minutes (09:00 - 21:00)"),
                    value: _sedentary,
                    activeThumbColor: const Color(0xFFF5BE53),
                    onChanged: connected
                        ? (v) {
                            setState(() => _sedentary = v);
                            ble.setSedentaryReminder(
                              enabled: v,
                              intervalMinutes: _sedMin.round(),
                            );
                            _toast("Sedentary reminder updated");
                          }
                        : null,
                  ),
                  Slider(
                    value: _sedMin,
                    min: 30,
                    max: 120,
                    divisions: 6,
                    label: "${_sedMin.round()} min",
                    activeColor: const Color(0xFFF5BE53),
                    onChanged: (v) => setState(() => _sedMin = v),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
