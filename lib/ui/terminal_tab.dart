import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/watch_ble_service.dart';

class TerminalTab extends StatelessWidget {
  final WatchBleService ble;

  const TerminalTab({super.key, required this.ble});

  void _copyAll(BuildContext context) {
    if (ble.logs.isEmpty) return;
    String all = ble.logs.reversed.join("\n");
    Clipboard.setData(ClipboardData(text: all));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("All logs copied to clipboard!")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Terminal Logs (${ble.logs.length})",
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _copyAll(context),
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text("Copy All"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF5BE53),
                      foregroundColor: Colors.black,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => ble.logs.clear(),
                    child: const Text("Clear"),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: ble.logs.isEmpty
                  ? const Center(
                      child: Text("Waiting for connection...",
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    )
                  : ListView.builder(
                      itemCount: ble.logs.length,
                      itemBuilder: (context, i) {
                        String line = ble.logs[i];
                        Color color = line.contains("RX")
                            ? const Color(0xFF00E5FF)
                            : (line.contains("error") || line.contains("fail")
                                ? Colors.redAccent
                                : (line.contains("Dispatched") ||
                                        line.contains("Auto-synced")
                                    ? const Color(0xFFF5BE53)
                                    : Colors.white70));
                        return Text(
                          line,
                          style: TextStyle(
                              fontFamily: "monospace",
                              fontSize: 11,
                              color: color),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
