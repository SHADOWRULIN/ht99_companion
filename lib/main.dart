import 'package:flutter/material.dart';
import 'watch_controller.dart';

void main() => runApp(const MaterialApp(home: WatchApp()));

class WatchApp extends StatefulWidget {
  const WatchApp({super.key});

  @override
  State<WatchApp> createState() => _WatchAppState();
}

class _WatchAppState extends State<WatchApp> {
  final WatchController _controller = WatchController();
  String _status = "Press button to scan for HT99";
  bool _isConnected = false;

  void _startConnect() {
    _controller.connectToWatch(
      onStatus: (msg) => setState(() => _status = msg),
      onConnected: () => setState(() => _isConnected = true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("HT99 Companion")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isConnected ? Icons.watch : Icons.watch_off,
                size: 80,
                color: _isConnected ? Colors.green : Colors.grey,
              ),
              const SizedBox(height: 20),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 30),
              if (!_isConnected)
                ElevatedButton(
                  onPressed: _startConnect,
                  child: const Text("Connect to HT99"),
                ),
              if (_isConnected) ...[
                ElevatedButton(
                  onPressed: () async {
                    await _controller.syncTimeNow();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Time sync sent!")),
                    );
                  },
                  child: const Text("Sync Phone Time"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
