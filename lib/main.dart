import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'watch_controller.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const Ht99App());
}

class Ht99App extends StatelessWidget {
  const Ht99App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "HT99 Manager",
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        cardColor: const Color(0xFF1A1D27),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C5CE7),
          secondary: Color(0xFF00CEC9),
          surface: Color(0xFF1A1D27),
        ),
        useMaterial3: true,
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  final WatchController _ctrl = WatchController();
  late TabController _tabController;

  String _status = "Ready to Connect";
  bool _connected = false;
  bool _connecting = false;

  final TextEditingController _hexController =
      TextEditingController(text: "AB 00 04");
  final TextEditingController _notifTitle =
      TextEditingController(text: "WhatsApp");
  final TextEditingController _notifBody =
      TextEditingController(text: "Hello from HT99 Companion!");

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  void _onConnect() {
    setState(() {
      _connecting = true;
      _status = "Scanning for HT99...";
    });

    _ctrl.connect(
      onStatus: (msg) => setState(() => _status = msg),
      onConnected: () => setState(() {
        _connected = true;
        _connecting = false;
      }),
      onData: () => setState(() {}),
    );
  }

  void _onDisconnect() async {
    await _ctrl.disconnect();
    setState(() {
      _connected = false;
      _status = "Disconnected";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("HT99 Manager Pro",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A1D27),
        elevation: 0,
        actions: [
          if (_connected)
            IconButton(
              icon: const Icon(Icons.sync, color: Color(0xFF00CEC9)),
              onPressed: () => _ctrl.readDirectBattery(() => setState(() {})),
              tooltip: "Refresh Data",
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF6C5CE7),
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_rounded), text: "Controls"),
            Tab(icon: Icon(Icons.terminal_rounded), text: "Terminal"),
            Tab(icon: Icon(Icons.account_tree_rounded), text: "Services"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildControlsTab(),
          _buildTerminalTab(),
          _buildServicesTab(),
        ],
      ),
    );
  }

  Widget _buildControlsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Connection Header Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1D27),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _connected
                  ? const Color(0xFF00CEC9).withOpacity(0.5)
                  : Colors.white10,
            ),
          ),
          child: Column(
            children: [
              Icon(
                _connected ? Icons.watch : Icons.watch_off_rounded,
                size: 64,
                color: _connected ? const Color(0xFF00CEC9) : Colors.grey,
              ),
              const SizedBox(height: 12),
              Text(
                _connected ? "HT99 Connected" : "Watch Disconnected",
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.white60),
              ),
              const SizedBox(height: 16),
              if (!_connected)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _connecting ? null : _onConnect,
                    icon: _connecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.bluetooth_searching),
                    label:
                        Text(_connecting ? "Searching..." : "Connect to HT99"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C5CE7),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: _onDisconnect,
                    icon: const Icon(Icons.bluetooth_disabled,
                        color: Colors.redAccent),
                    label: const Text("Disconnect",
                        style: TextStyle(color: Colors.redAccent)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Live Telemetry Cards
        Row(
          children: [
            Expanded(
              child: _metricCard(
                icon: Icons.battery_charging_full_rounded,
                color: const Color(0xFF00CEC9),
                value: "${_ctrl.batteryLevel}%",
                title: "Battery",
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metricCard(
                icon: Icons.directions_walk_rounded,
                color: const Color(0xFFFFA502),
                value: "${_ctrl.stepCount}",
                title: "Steps",
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metricCard(
                icon: Icons.favorite_rounded,
                color: const Color(0xFFFF4757),
                value: "${_ctrl.heartRate}",
                title: "BPM",
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Watch Actions Card
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Core Actions",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF6C5CE7),
                    child: Icon(Icons.access_time_filled_rounded,
                        color: Colors.white),
                  ),
                  title: const Text("Sync Accurate Time"),
                  subtitle: const Text("Syncs phone RTC down to the second"),
                  trailing: ElevatedButton(
                    onPressed: _connected
                        ? () async {
                            await _ctrl.syncTime();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text("Time sync packet broadcasted!")),
                            );
                          }
                        : null,
                    child: const Text("Sync"),
                  ),
                ),
                const Divider(color: Colors.white10),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFFA502),
                    child: Icon(Icons.vibration_rounded, color: Colors.white),
                  ),
                  title: const Text("Find Watch (Ring)"),
                  subtitle: const Text("Triggers Immediate Alert vibration"),
                  trailing: ElevatedButton(
                    onPressed: _connected
                        ? () async {
                            await _ctrl.ringWatch();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text("Vibration alert sent!")),
                            );
                          }
                        : null,
                    child: const Text("Ring"),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Notification Sender Card
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Push Notification Test",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: _notifTitle,
                  decoration: const InputDecoration(
                    labelText: "App / Title",
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _notifBody,
                  decoration: const InputDecoration(
                    labelText: "Message Body",
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _connected
                        ? () async {
                            await _ctrl.pushNotification(
                                _notifTitle.text, _notifBody.text);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text("Notification pushed to watch!")),
                            );
                          }
                        : null,
                    icon: const Icon(Icons.send_rounded),
                    label: const Text("Push to Watch Screen"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00CEC9),
                      foregroundColor: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _metricCard(
      {required IconData icon,
      required Color color,
      required String value,
      required String title}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(value,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(title,
              style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _buildTerminalTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hexController,
                  decoration: const InputDecoration(
                    labelText: "Hex Bytes (e.g. AB 00 04)",
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _connected
                    ? () {
                        try {
                          List<int> bytes = _hexController.text
                              .trim()
                              .split(RegExp(r'\s+'))
                              .map((s) => int.parse(s, radix: 16))
                              .toList();
                          _ctrl.writeRaw(bytes);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text("Sent: ${bytes.length} bytes")),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Invalid Hex: $e")),
                          );
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C5CE7)),
                child: const Text("Send"),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: ListView.builder(
                itemCount: _ctrl.logs.length,
                itemBuilder: (context, index) {
                  String l = _ctrl.logs[index];
                  Color c = l.contains("RX:")
                      ? const Color(0xFF00CEC9)
                      : (l.contains("TX")
                          ? const Color(0xFFFFA502)
                          : Colors.white70);
                  return Text(
                    l,
                    style: TextStyle(
                        fontFamily: "monospace", fontSize: 11, color: c),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicesTab() {
    if (_ctrl.discoveredTree.isEmpty) {
      return const Center(
          child: Text("Connect watch to inspect GATT services"));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _ctrl.discoveredTree.length,
      itemBuilder: (context, index) {
        var s = _ctrl.discoveredTree[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ExpansionTile(
            title: Text(
              "Service: ${s['service']}",
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00CEC9)),
            ),
            children: (s['chars'] as List<String>).map((c) {
              return ListTile(
                dense: true,
                title: Text(c,
                    style:
                        const TextStyle(fontSize: 11, fontFamily: "monospace")),
                leading: const Icon(Icons.arrow_right, size: 16),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
