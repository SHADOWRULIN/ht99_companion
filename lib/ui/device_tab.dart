import 'package:flutter/material.dart';
import '../services/watch_ble_service.dart';
import 'message_push_screen.dart';
import 'dial_push_screen.dart';

class DeviceTab extends StatelessWidget {
  final WatchBleService ble;
  final VoidCallback onConnectTrigger;

  const DeviceTab(
      {super.key, required this.ble, required this.onConnectTrigger});

  @override
  Widget build(BuildContext context) {
    bool connected = ble.isConnected;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Watch Connection Header
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
                child: Icon(connected ? Icons.watch : Icons.watch_off,
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
                      connected
                          ? "Connected (${ble.telemetry.batteryLevel}%)"
                          : "Disconnected",
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed:
                    connected ? () => ble.disconnect() : onConnectTrigger,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black),
                child: Text(connected ? "Disconnect" : "Connect"),
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
              _tile(
                context,
                icon: Icons.notifications_active_rounded,
                color: Colors.amber,
                title: "Message push",
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => MessagePushScreen(ble: ble))),
              ),
              const Divider(height: 1, indent: 64),
              _tile(
                context,
                icon: Icons.vibration,
                color: const Color(0xFFFF4757),
                title: "Find your bracelet",
                onTap: connected ? () => ble.ringWatch() : null,
              ),
              const Divider(height: 1, indent: 64),
              _tile(
                context,
                icon: Icons.wallpaper_rounded,
                color: Colors.purpleAccent,
                title: "Dial push",
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => DialPushScreen(ble: ble))),
              ),
              const Divider(height: 1, indent: 64),
              _tile(
                context,
                icon: Icons.cloud_sync,
                color: Colors.cyan,
                title: "Sync Weather",
                onTap: connected ? () => ble.pushWeather(31, 1, 35, 27) : null,
              ),
              const Divider(height: 1, indent: 64),
              _tile(
                context,
                icon: Icons.local_drink_rounded,
                color: Colors.blueAccent,
                title: "Reminder to drink water",
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("Water reminder interval active")));
                },
              ),
              const Divider(height: 1, indent: 64),
              _tile(
                context,
                icon: Icons.airline_seat_recline_normal_rounded,
                color: Colors.orange,
                title: "Recumbent reminder",
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("Sedentary reminder interval active")));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext ctx,
      {required IconData icon,
      required Color color,
      required String title,
      VoidCallback? onTap}) {
    return ListTile(
      leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded,
          size: 14, color: Colors.grey),
      onTap: onTap,
    );
  }
}
