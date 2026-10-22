import 'package:flutter/material.dart';
import '../services/watch_ble_service.dart';
import 'message_push_screen.dart';
import 'dial_push_screen.dart';
import 'alarm_setting_screen.dart';
import 'drink_water_screen.dart';

class DeviceTab extends StatelessWidget {
  final WatchBleService ble;
  final VoidCallback onConnectTrigger;

  const DeviceTab(
      {super.key, required this.ble, required this.onConnectTrigger});

  @override
  Widget build(BuildContext context) {
    bool connected = ble.isConnected;
    String batteryText = ble.telemetry.batteryLevel >= 0
        ? "(${ble.telemetry.batteryLevel}%)"
        : "(Loading...)";

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2E3030), Color(0xFF202122)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF5BE53).withOpacity(0.3)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFFF5BE53).withOpacity(0.15),
                child:
                    const Icon(Icons.watch_rounded, color: Color(0xFFF5BE53), size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("HT99 Smartwatch",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold)),
                    Text(
                      connected ? "Connected $batteryText" : "Disconnected",
                      style: const TextStyle(
                          color: Color(0xFFC5D1CB), fontSize: 13),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed:
                    connected ? () => ble.disconnect() : onConnectTrigger,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF5BE53),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(connected ? "Disconnect" : "Connect"),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ListTile(
            leading: const Icon(Icons.cloud_sync_rounded, color: Color(0xFFF5BE53)),
            title: const Text("Sync weather"),
            subtitle: const Text("Current conditions and today's high/low for Karachi"),
            trailing: const Icon(Icons.chevron_right),
            onTap: connected ? () async {
              final sent = await ble.syncWeather();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(sent
                    ? "Weather command sent. Check the watch display."
                    : "Weather sync failed. Open Terminal for the reason.")),
              );
            } : null,
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
                icon: Icons.alarm_rounded,
                color: Colors.deepOrange,
                title: "Alarm setting",
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AlarmSettingScreen(ble: ble))),
              ),
              const Divider(height: 1, indent: 64),
              _tile(
                context,
                icon: Icons.favorite_rounded,
                color: Colors.pinkAccent,
                title: "Heart rate detection",
                onTap: connected ? () => ble.measureHeartRateLive() : null,
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
                icon: Icons.local_drink_rounded,
                color: Colors.blueAccent,
                title: "Reminder to drink water",
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => DrinkWaterScreen(ble: ble))),
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
