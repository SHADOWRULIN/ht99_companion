import 'package:flutter/material.dart';
import '../services/watch_ble_service.dart';
import 'message_push_screen.dart';
import 'dial_push_screen.dart';
import 'alarm_setting_screen.dart';
import 'drink_water_screen.dart';
import 'sync_settings_screen.dart';

class DeviceTab extends StatelessWidget {
  final WatchBleService ble;
  final VoidCallback onConnectTrigger;

  const DeviceTab(
      {super.key, required this.ble, required this.onConnectTrigger});

  void _showTestNotifDialog(BuildContext context) {
    final titleCtrl = TextEditingController(text: "WhatsApp");
    final bodyCtrl =
        TextEditingController(text: "Hello from Apple Watch Companion!");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Send Test Notification"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: "Title / Sender"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: bodyCtrl,
              decoration: const InputDecoration(labelText: "Message Content"),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              ble.pushNotification(titleCtrl.text, bodyCtrl.text);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text("Test notification sent to watch!")),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF5BE53),
              foregroundColor: Colors.black,
            ),
            child: const Text("Send"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool connected = ble.isConnected;
    String batteryText = ble.telemetry.batteryLevel >= 0
        ? "(${ble.telemetry.batteryLevel}%)"
        : "(Syncing...)";

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
            border: Border.all(
                color: const Color(0xFFF5BE53).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor:
                    const Color(0xFFF5BE53).withValues(alpha: 0.15),
                child:
                    const Icon(Icons.apple, color: Color(0xFFF5BE53), size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Apple Watch HT99",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
        const SizedBox(height: 16),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Column(
            children: [
              _tile(
                context,
                icon: Icons.tune_rounded,
                color: const Color(0xFFF5BE53),
                title: "Sync, Time Format & Weather",
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => SyncSettingsScreen(ble: ble)),
                ),
              ),
              const Divider(height: 1, indent: 64),
              _tile(
                context,
                icon: Icons.notifications_active_rounded,
                color: Colors.amber,
                title: "Message push",
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => MessagePushScreen(ble: ble)),
                ),
              ),
              const Divider(height: 1, indent: 64),
              _tile(
                context,
                icon: Icons.send_to_mobile_rounded,
                color: Colors.tealAccent,
                title: "Send test notification",
                onTap: connected ? () => _showTestNotifDialog(context) : null,
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
                      builder: (_) => AlarmSettingScreen(ble: ble)),
                ),
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
                  MaterialPageRoute(builder: (_) => DialPushScreen(ble: ble)),
                ),
              ),
              const Divider(height: 1, indent: 64),
              _tile(
                context,
                icon: Icons.local_drink_rounded,
                color: Colors.blueAccent,
                title: "Reminder to drink water",
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DrinkWaterScreen(ble: ble)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(
    BuildContext ctx, {
    required IconData icon,
    required Color color,
    required String title,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded,
          size: 14, color: Colors.grey),
      onTap: onTap,
    );
  }
}
