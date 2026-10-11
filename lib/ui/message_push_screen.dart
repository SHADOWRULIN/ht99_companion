import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/watch_ble_service.dart';

class MessagePushScreen extends StatefulWidget {
  final WatchBleService ble;

  const MessagePushScreen({super.key, required this.ble});

  @override
  State<MessagePushScreen> createState() => _MessagePushScreenState();
}

class _MessagePushScreenState extends State<MessagePushScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  static const MethodChannel _phoneChannel =
      MethodChannel("com.ht99.companion/phone");

  final List<Map<String, String>> personalApps = [
    {"name": "WhatsApp", "pkg": "com.whatsapp"},
    {"name": "Instagram", "pkg": "com.instagram.android"},
    {"name": "Facebook", "pkg": "com.facebook.katana"},
    {"name": "Twitter (X)", "pkg": "com.twitter.android"},
    {"name": "Telegram", "pkg": "org.telegram.messenger"},
    {"name": "Snapchat", "pkg": "com.snapchat.android"},
    {"name": "TikTok", "pkg": "com.zhiliaoapp.musically"},
    {"name": "Binance", "pkg": "com.binance.dev"},
  ];

  final List<Map<String, String>> systemApps = [
    {"name": "Phone / Call Reminder", "pkg": "com.android.server.telecom"},
    {"name": "SMS Messages", "pkg": "com.google.android.apps.messaging"},
    {"name": "Gmail", "pkg": "com.google.android.gm"},
    {"name": "Calendar", "pkg": "com.google.android.calendar"},
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _checkPermission();
  }

  void _checkPermission() async {
    bool enabled =
        await _phoneChannel.invokeMethod("isNotificationListenerEnabled") ??
            false;
    if (!enabled && mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Reminder"),
          content: const Text(
              "It is necessary to open the auxiliary service function to prevent some mobile phones from receiving the message push."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _phoneChannel.invokeMethod("openNotificationSettings");
              },
              child: const Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Message push"),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFFF5BE53),
          tabs: const [
            Tab(text: "Personal app"),
            Tab(text: "System app"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildAppList(personalApps),
          _buildAppList(systemApps),
        ],
      ),
    );
  }

  Widget _buildAppList(List<Map<String, String>> apps) {
    return ListView.separated(
      itemCount: apps.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        String name = apps[i]["name"]!;
        String pkg = apps[i]["pkg"]!;
        bool isEnabled = widget.ble.enabledPackages.contains(pkg);

        return SwitchListTile(
          title: Text(name),
          value: isEnabled,
          activeColor: const Color(0xFFF5BE53),
          onChanged: (val) {
            setState(() {
              if (val) {
                widget.ble.enabledPackages.add(pkg);
              } else {
                widget.ble.enabledPackages.remove(pkg);
              }
            });
          },
        );
      },
    );
  }
}
