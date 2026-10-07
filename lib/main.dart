import 'package:flutter/material.dart';
import 'watch_controller.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: WatchDashboard(),
  ));
}

class WatchDashboard extends StatefulWidget {
  const WatchDashboard({super.key});

  @override
  State<WatchDashboard> createState() => _WatchDashboardState();
}

class _WatchDashboardState extends State<WatchDashboard> {
  final WatchController _watch = WatchController();
  String _status = "Ready to connect";
  bool _isConnected = false;
  bool _isConnecting = false;

  void _connect() {
    setState(() {
      _isConnecting = true;
      _status = "Connecting...";
    });

    _watch.connectToWatch(
      onStatus: (msg) => setState(() => _status = msg),
      onConnected: () => setState(() {
        _isConnected = true;
        _isConnecting = false;
      }),
      onDataUpdated: () => setState(() {}),
    );
  }

  void _disconnect() async {
    await _watch.disconnect();
    setState(() {
      _isConnected = false;
      _status = "Disconnected";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text("HT99 Smartwatch Manager"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: "Refresh Metrics",
              onPressed: () => _watch.requestBatteryAndSteps(),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Status Card
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Icon(
                      _isConnected ? Icons.watch : Icons.watch_off_outlined,
                      size: 64,
                      color: _isConnected ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isConnected ? "HT99 Connected" : "Watch Disconnected",
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 16),
                    if (!_isConnected)
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isConnecting ? null : _connect,
                          icon: _isConnecting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.bluetooth_searching),
                          label: Text(_isConnecting
                              ? "Scanning..."
                              : "Connect to HT99"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: _disconnect,
                          icon: const Icon(Icons.bluetooth_disabled,
                              color: Colors.red),
                          label: const Text("Disconnect",
                              style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Telemetry Cards
            if (_isConnected) ...[
              Row(
                children: [
                  Expanded(
                    child: Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Icon(Icons.battery_charging_full,
                                color: Colors.teal, size: 36),
                            const SizedBox(height: 8),
                            Text(
                              "${_watch.batteryLevel}%",
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                            const Text("Battery",
                                style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Icon(Icons.directions_walk,
                                color: Colors.orange, size: 36),
                            const SizedBox(height: 8),
                            Text(
                              "${_watch.stepCount}",
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                            const Text("Today's Steps",
                                style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Control Actions
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Watch Controls",
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.indigoAccent,
                          child: Icon(Icons.access_time, color: Colors.white),
                        ),
                        title: const Text("Sync Accurate Time"),
                        subtitle: const Text(
                            "Sets watch RTC clock to phone's current time"),
                        trailing: ElevatedButton(
                          onPressed: () async {
                            await _watch.syncTimeNow();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text("Time sync packet sent to HT99!")),
                              );
                            }
                          },
                          child: const Text("Sync"),
                        ),
                      ),
                      const Divider(),
                      ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.amber,
                          child: Icon(Icons.vibration, color: Colors.white),
                        ),
                        title: const Text("Find Watch"),
                        subtitle: const Text("Sends vibration trigger to HT99"),
                        trailing: ElevatedButton(
                          onPressed: () async {
                            await _watch.findWatch();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text("Vibration alert triggered!")),
                              );
                            }
                          },
                          child: const Text("Ring"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
