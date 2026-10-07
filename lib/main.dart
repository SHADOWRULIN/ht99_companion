import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'watch_controller.dart';

void main() {
  runApp(const Ht99MasterApp());
}

class Ht99MasterApp extends StatefulWidget {
  const Ht99MasterApp({super.key});

  @override
  State<Ht99MasterApp> createState() => _Ht99MasterAppState();
}

class _Ht99MasterAppState extends State<Ht99MasterApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void toggleTheme(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "HT99 Manager Pro",
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF6F8FB),
        cardColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFFF5722),
          secondary: Color(0xFF00B4D8),
          surface: Colors.white,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0F15),
        cardColor: const Color(0xFF161922),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF5722),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF161922),
        ),
        useMaterial3: true,
      ),
      home: MainShell(onThemeChanged: toggleTheme, currentTheme: _themeMode),
    );
  }
}

class MainShell extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  final ThemeMode currentTheme;

  const MainShell(
      {super.key, required this.onThemeChanged, required this.currentTheme});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final WatchController _watch = WatchController();
  int _tabIndex = 0;

  bool _connected = false;
  bool _connecting = false;
  String _status = "Ready to connect";
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;

  bool _waterReminder = false;
  bool _sedentaryReminder = false;
  int _stepGoal = 10000;

  @override
  void initState() {
    super.initState();
    FlutterBluePlus.adapterState.listen((state) {
      setState(() => _adapterState = state);
    });
  }

  void _startConnecting() {
    setState(() {
      _connecting = true;
      _status = "Scanning for HT99...";
    });

    _showConnectingDialog();

    _watch.connect(
      onStatus: (msg) {
        setState(() => _status = msg);
      },
      onConnected: () {
        setState(() {
          _connected = true;
          _connecting = false;
        });
        if (Navigator.canPop(context)) Navigator.pop(context);
      },
      onData: () => setState(() {}),
    );
  }

  void _showConnectingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text("Connecting to HT99", textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              const CircularProgressIndicator(color: Color(0xFFFF5722)),
              const SizedBox(height: 20),
              Text(_status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13)),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceAround,
          actions: [
            TextButton(
              onPressed: () async {
                await _watch.stopScan();
                setState(() => _connecting = false);
                if (Navigator.canPop(context)) Navigator.pop(context);
              },
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                _watch.stopScan();
                _watch.connect(
                  onStatus: (msg) => setState(() => _status = msg),
                  onConnected: () {
                    setState(() {
                      _connected = true;
                      _connecting = false;
                    });
                    if (Navigator.canPop(context)) Navigator.pop(context);
                  },
                  onData: () => setState(() {}),
                );
              },
              child: const Text("Search Again"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildHomeTab(),
      _buildDeviceTab(),
      _buildMyTab(),
      _buildTerminalTab(),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Warning Card: Bluetooth Off
            if (_adapterState != BluetoothAdapterState.on &&
                _adapterState != BluetoothAdapterState.unknown)
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bluetooth_disabled,
                        color: Colors.redAccent),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        "Bluetooth is turned off on your phone.",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => FlutterBluePlus.turnOn(),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white),
                      child: const Text("Turn On"),
                    ),
                  ],
                ),
              ),
            Expanded(child: pages[_tabIndex]),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
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

  // --- TAB 1: HOME ---
  Widget _buildHomeTab() {
    double progress = (_watch.stepCount / _stepGoal).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Home",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: _connected ? () => _watch.syncTime() : null,
              tooltip: "Sync Watch",
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
                    width: 160,
                    height: 160,
                    child: CircularProgressIndicator(
                      value: progress == 0 ? 0.05 : progress,
                      strokeWidth: 12,
                      backgroundColor: Colors.white12,
                      color: const Color(0xFFFF5722),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    children: [
                      Text("${_watch.stepCount}",
                          style: const TextStyle(
                              fontSize: 34, fontWeight: FontWeight.bold)),
                      Text("goal: $_stepGoal",
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
                  _stat("${_watch.caloriesKcal}", "kcal"),
                  _stat("${_watch.distanceKm.toStringAsFixed(2)}", "km"),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
                child: _metricTile(Icons.nightlight_round, Colors.indigoAccent,
                    "Sleep", "-- h")),
            const SizedBox(width: 12),
            Expanded(
              child: _metricTile(
                Icons.favorite_rounded,
                Colors.redAccent,
                "HeartRate",
                _watch.heartRate > 0 ? "${_watch.heartRate} bpm" : "-- bpm",
                onTap: _connected ? () => _watch.triggerHeartRate() : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- TAB 2: DEVICE ---
  Widget _buildDeviceTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFFFF5722), Color(0xFFFF7043)]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.white24,
                child: Icon(_connected ? Icons.watch : Icons.watch_off,
                    color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Model: HT99",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    Text(
                      _connected
                          ? "Connected (${_watch.batteryLevel}% Battery)"
                          : "Disconnected",
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: _connecting
                    ? null
                    : (_connected
                        ? () => setState(() => _connected = false)
                        : _startConnecting),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black),
                child: Text(_connected ? "Disconnect" : "Connect"),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Column(
            children: [
              _actionTile(Icons.sync, Colors.cyan, "Sync Phone Time",
                  "Broadcasts CTS Server clock", () async {
                await _watch.syncTime();
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Time sync broadcasted!")));
              }),
              _actionTile(Icons.vibration, Colors.amber, "Find your bracelet",
                  "Triggers Immediate Alert vibration", () async {
                await _watch.ringWatch();
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Vibration alert sent!")));
              }),
              _actionTile(
                  Icons.notifications_active_rounded,
                  Colors.green,
                  "Message push",
                  "Send test WhatsApp message",
                  () => _showNotifDialog()),
              _switchTile(Icons.local_drink_rounded, Colors.blueAccent,
                  "Reminder to drink water", _waterReminder, (v) {
                setState(() => _waterReminder = v);
                _watch.setWaterReminder(v);
              }),
              _switchTile(Icons.airline_seat_recline_normal_rounded,
                  Colors.orange, "Recumbent reminder", _sedentaryReminder, (v) {
                setState(() => _sedentaryReminder = v);
                _watch.setSedentaryReminder(v);
              }),
              _actionTile(
                  Icons.wallpaper_rounded,
                  Colors.purpleAccent,
                  "Dial push",
                  "320x385 Custom watch face",
                  () => _showDialGallery()),
            ],
          ),
        ),
      ],
    );
  }

  // --- TAB 3: MY (Theme & Profile) ---
  Widget _buildMyTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text("Settings & Profile",
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
                subtitle: Text(widget.currentTheme == ThemeMode.dark
                    ? "Dark Mode"
                    : "Light Mode"),
                trailing: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.light, icon: Icon(Icons.light_mode)),
                    ButtonSegment(
                        value: ThemeMode.dark, icon: Icon(Icons.dark_mode)),
                  ],
                  selected: {widget.currentTheme},
                  onSelectionChanged: (set) => widget.onThemeChanged(set.first),
                ),
              ),
              const Divider(height: 1, indent: 64),
              ListTile(
                leading: const Icon(Icons.directions_run_rounded),
                title: const Text("Step Target"),
                subtitle: Text("$_stepGoal steps"),
                trailing: DropdownButton<int>(
                  value: _stepGoal,
                  items: [5000, 8000, 10000, 15000]
                      .map((v) => DropdownMenuItem(value: v, child: Text("$v")))
                      .toList(),
                  onChanged: (v) => setState(() => _stepGoal = v ?? 10000),
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
                title: Text("Chipset"),
                subtitle: Text("MediaTek MTK2502C (320x385 IPS)"),
              ),
              Divider(height: 1, indent: 64),
              ListTile(
                leading: Icon(Icons.bluetooth_connected_rounded),
                title: Text("BLE Target MAC"),
                subtitle: Text("F9:47:B2:F6:EC:7C"),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- TAB 4: TERMINAL ---
  Widget _buildTerminalTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  "Connected Pipe: ${_watch.dogpWriteChar?.uuid.str.substring(0, 4) ?? 'None'}",
                  style: const TextStyle(fontSize: 12)),
              TextButton(
                  onPressed: () => setState(() => _watch.logs.clear()),
                  child: const Text("Clear")),
            ],
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.black, borderRadius: BorderRadius.circular(16)),
              child: ListView.builder(
                itemCount: _watch.logs.length,
                itemBuilder: (context, i) {
                  String l = _watch.logs[i];
                  Color c = l.contains("RX:")
                      ? Colors.cyanAccent
                      : (l.contains("TX")
                          ? Colors.amberAccent
                          : Colors.white70);
                  return Text(l,
                      style: TextStyle(
                          fontFamily: "monospace", fontSize: 11, color: c));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Modals ---
  void _showDialGallery() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("320x385 Watch Face Dials",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _dialPreview("Classic Chrono", Colors.blueGrey),
                _dialPreview("Sport Digital", Colors.deepOrange),
                _dialPreview("Minimal Gold", Colors.amber),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _connected
                    ? () {
                        Navigator.pop(ctx);
                        _watch.pushDial([0xAB, 0x00, 0x01], (p) {});
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text("Streaming dial data...")));
                      }
                    : null,
                icon: const Icon(Icons.upload_rounded),
                label: const Text("Push Selected Dial"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialPreview(String name, Color color) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 100,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(16)),
          child: const Center(
              child: Text("10:09",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold))),
        ),
        const SizedBox(height: 6),
        Text(name, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _stat(String v, String l) => Column(children: [
        Text(v,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Text(l, style: const TextStyle(fontSize: 11, color: Colors.grey))
      ]);
  Widget _metricTile(IconData i, Color c, String t, String v,
          {VoidCallback? onTap}) =>
      InkWell(
          onTap: onTap,
          child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(i, color: c),
                    const SizedBox(height: 8),
                    Text(t,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(v,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold))
                  ])));
  Widget _actionTile(
          IconData i, Color c, String t, String s, VoidCallback onTap) =>
      ListTile(
          leading: CircleAvatar(
              backgroundColor: c.withOpacity(0.15), child: Icon(i, color: c)),
          title: Text(t),
          subtitle: Text(s, style: const TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.chevron_right),
          onTap: _connected ? onTap : null);
  Widget _switchTile(
          IconData i, Color c, String t, bool v, ValueChanged<bool> onChange) =>
      SwitchListTile(
          secondary: CircleAvatar(
              backgroundColor: c.withOpacity(0.15), child: Icon(i, color: c)),
          title: Text(t),
          value: v,
          onChanged: _connected ? onChange : null);

  void _showNotifDialog() {
    final t = TextEditingController(text: "WhatsApp");
    final b = TextEditingController(text: "Hello from HT99 Companion!");
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Push Notification"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: t,
              decoration: const InputDecoration(labelText: "App Name")),
          TextField(
              controller: b,
              decoration: const InputDecoration(labelText: "Body")),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              _watch.sendNotification(t.text, b.text);
              Navigator.pop(ctx);
            },
            child: const Text("Send"),
          ),
        ],
      ),
    );
  }
}
