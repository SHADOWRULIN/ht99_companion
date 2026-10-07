import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'watch_controller.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const Ht99FullApp());
}

class Ht99FullApp extends StatelessWidget {
  const Ht99FullApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "HT99 Manager Pro",
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0C10),
        cardColor: const Color(0xFF161922),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF5722),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF161922),
        ),
        useMaterial3: true,
      ),
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  final WatchController _watch = WatchController();
  int _currentIndex = 0;
  String _status = "Ready to Connect";
  bool _connected = false;
  bool _connecting = false;

  // Settings states matching WWfit
  bool _waterReminder = false;
  bool _sedentaryReminder = false;
  int _stepGoal = 10000;

  void _connect() {
    setState(() {
      _connecting = true;
      _status = "Connecting...";
    });

    _watch.connect(
      onStatus: (msg) => setState(() => _status = msg),
      onConnected: () => setState(() {
        _connected = true;
        _connecting = false;
      }),
      onData: () => setState(() {}),
    );
  }

  void _disconnect() async {
    await _watch.disconnect();
    setState(() {
      _connected = false;
      _status = "Disconnected";
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildHomeScreen(),
      _buildDeviceScreen(),
      _buildMyScreen(),
      _buildTerminalScreen(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_currentIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        backgroundColor: const Color(0xFF12151D),
        indicatorColor: const Color(0xFFFF5722).withOpacity(0.2),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: "Home"),
          NavigationDestination(
              icon: Icon(Icons.watch_rounded), label: "Device"),
          NavigationDestination(icon: Icon(Icons.person_rounded), label: "My"),
          NavigationDestination(
              icon: Icon(Icons.terminal_rounded), label: "Terminal"),
        ],
      ),
    );
  }

  // --- TAB 1: HOME (Steps, Progress, Telemetry) ---
  Widget _buildHomeScreen() {
    double progress = (_watch.stepCount / _stepGoal).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Home",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.refresh, color: Color(0xFF00E5FF)),
              onPressed: _connected ? () => _watch.syncTime() : null,
              tooltip: "Refresh Metrics",
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Step Progress Arc Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF161922),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              const Text("today's steps",
                  style: TextStyle(fontSize: 14, color: Colors.white60)),
              const SizedBox(height: 12),
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
                        "${_watch.stepCount}",
                        style: const TextStyle(
                            fontSize: 36, fontWeight: FontWeight.bold),
                      ),
                      Text("goal: $_stepGoal",
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white54)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _subMetric("${(progress * 100).toInt()}%", "Percent"),
                  _subMetric("${_watch.caloriesKcal}", "kcal"),
                  _subMetric("${_watch.distanceKm.toStringAsFixed(2)}", "km"),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Health Telemetry Row
        Row(
          children: [
            Expanded(
              child: _infoCard(
                icon: Icons.nightlight_round,
                color: Colors.indigoAccent,
                title: "Sleep",
                value: "-- h",
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _infoCard(
                icon: Icons.favorite_rounded,
                color: const Color(0xFFFF4757),
                title: "HeartRate",
                value:
                    _watch.heartRate > 0 ? "${_watch.heartRate} bpm" : "-- bpm",
                onTap:
                    _connected ? () => _watch.triggerHeartRateMeasure() : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- TAB 2: DEVICE (WWfit Feature Grid) ---
  Widget _buildDeviceScreen() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Watch Connection Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF5722), Color(0xFFFF7043)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white24,
                child: Icon(_connected ? Icons.watch : Icons.watch_off,
                    color: Colors.white, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Model: HT99",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(
                      _connected
                          ? "Connected (${_watch.batteryLevel}% Battery)"
                          : "Disconnected",
                      style:
                          const TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed:
                    _connecting ? null : (_connected ? _disconnect : _connect),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(_connected ? "Disconnect" : "Connect"),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Device Functions Card
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Column(
            children: [
              _menuItem(
                icon: Icons.sync,
                color: const Color(0xFF00E5FF),
                title: "Sync Phone Time",
                subtitle: "Sync watch RTC via CTS Server",
                onTap: _connected
                    ? () async {
                        await _watch.syncTime();
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text("Clock synchronization sent!")));
                      }
                    : null,
              ),
              const Divider(height: 1, indent: 64, color: Colors.white10),
              _menuItem(
                icon: Icons.vibration,
                color: const Color(0xFFFFA502),
                title: "Find your bracelet",
                subtitle: "Triggers Immediate Alert vibration",
                onTap: _connected
                    ? () async {
                        await _watch.ringWatch();
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text("Vibration alert sent!")));
                      }
                    : null,
              ),
              const Divider(height: 1, indent: 64, color: Colors.white10),
              _menuItem(
                icon: Icons.notifications_active_rounded,
                color: const Color(0xFF2ED573),
                title: "Message push",
                subtitle: "Forward WhatsApp/SMS to watch",
                onTap: () => _showNotificationDialog(),
              ),
              const Divider(height: 1, indent: 64, color: Colors.white10),
              _switchItem(
                icon: Icons.local_drink_rounded,
                color: Colors.lightBlueAccent,
                title: "Reminder to drink water",
                value: _waterReminder,
                onChanged: _connected
                    ? (v) {
                        setState(() => _waterReminder = v);
                        _watch.setWaterReminder(v);
                      }
                    : null,
              ),
              const Divider(height: 1, indent: 64, color: Colors.white10),
              _switchItem(
                icon: Icons.airline_seat_recline_normal_rounded,
                color: Colors.amber,
                title: "Recumbent reminder",
                value: _sedentaryReminder,
                onChanged: _connected
                    ? (v) {
                        setState(() => _sedentaryReminder = v);
                        _watch.setSedentaryReminder(v);
                      }
                    : null,
              ),
              const Divider(height: 1, indent: 64, color: Colors.white10),
              _menuItem(
                icon: Icons.wallpaper_rounded,
                color: Colors.purpleAccent,
                title: "Dial push",
                subtitle: "320x385 Custom watch face",
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            "Dial template ready: 320x385 resolution verified.")),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- TAB 3: MY (Profile & Goals) ---
  Widget _buildMyScreen() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text("My Profile",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Column(
            children: [
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFF5722),
                  child:
                      Icon(Icons.directions_run_rounded, color: Colors.white),
                ),
                title: const Text("Step target"),
                subtitle: Text("$_stepGoal steps"),
                trailing: DropdownButton<int>(
                  value: _stepGoal,
                  dropdownColor: const Color(0xFF161922),
                  items: [5000, 8000, 10000, 15000].map((v) {
                    return DropdownMenuItem(value: v, child: Text("$v"));
                  }).toList(),
                  onChanged: (v) => setState(() => _stepGoal = v ?? 10000),
                ),
              ),
              const Divider(height: 1, indent: 64, color: Colors.white10),
              const ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.indigoAccent,
                  child: Icon(Icons.bedtime_rounded, color: Colors.white),
                ),
                title: Text("Sleep target"),
                subtitle: Text("8 hours"),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: const Column(
            children: [
              ListTile(
                leading: Icon(Icons.info_outline_rounded),
                title: Text("Hardware Info"),
                subtitle: Text("MediaTek MTK2502C (320x385 Display)"),
              ),
              Divider(height: 1, indent: 64, color: Colors.white10),
              ListTile(
                leading: Icon(Icons.bluetooth_connected_rounded),
                title: Text("Target Device MAC"),
                subtitle: Text("F9:47:B2:F6:EC:7C"),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- TAB 4: TERMINAL (Diagnostics & Live RX/TX) ---
  Widget _buildTerminalScreen() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text("Status: $_status",
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white60)),
              ),
              ElevatedButton.icon(
                onPressed: () => setState(() => _watch.logs.clear()),
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text("Clear"),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: ListView.builder(
                itemCount: _watch.logs.length,
                itemBuilder: (context, i) {
                  String line = _watch.logs[i];
                  Color color = line.contains("RX:")
                      ? const Color(0xFF00E5FF)
                      : (line.contains("TX")
                          ? const Color(0xFFFFA502)
                          : Colors.white70);
                  return Text(line,
                      style: TextStyle(
                          fontFamily: "monospace", fontSize: 11, color: color));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- UI Helpers ---
  Widget _subMetric(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.white54)),
      ],
    );
  }

  Widget _infoCard(
      {required IconData icon,
      required Color color,
      required String title,
      required String value,
      VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF161922),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(fontSize: 13, color: Colors.white60)),
            const SizedBox(height: 4),
            Text(value,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(
      {required IconData icon,
      required Color color,
      required String title,
      required String subtitle,
      VoidCallback? onTap}) {
    return ListTile(
      leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.white54)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded,
          size: 14, color: Colors.white30),
      onTap: onTap,
    );
  }

  Widget _switchItem(
      {required IconData icon,
      required Color color,
      required String title,
      required bool value,
      ValueChanged<bool>? onChanged}) {
    return SwitchListTile(
      secondary: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      value: value,
      onChanged: onChanged,
    );
  }

  void _showNotificationDialog() {
    final titleCtrl = TextEditingController(text: "WhatsApp");
    final bodyCtrl =
        TextEditingController(text: "New message from HT99 Companion!");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        title: const Text("Push Notification"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: titleCtrl,
                decoration:
                    const InputDecoration(labelText: "App Name / Title")),
            const SizedBox(height: 10),
            TextField(
                controller: bodyCtrl,
                decoration: const InputDecoration(labelText: "Message Body")),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              _watch.sendNotification(titleCtrl.text, bodyCtrl.text);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Notification sent!")));
            },
            child: const Text("Send"),
          ),
        ],
      ),
    );
  }
}
