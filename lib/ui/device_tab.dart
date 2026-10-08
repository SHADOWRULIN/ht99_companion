import 'package:flutter/material.dart';
import '../services/watch_ble_service.dart';
import '../services/dial_service.dart';

class DeviceTab extends StatefulWidget {
  final WatchBleService ble;
  final VoidCallback onConnectTrigger;

  const DeviceTab(
      {super.key, required this.ble, required this.onConnectTrigger});

  @override
  State<DeviceTab> createState() => _DeviceTabState();
}

class _DeviceTabState extends State<DeviceTab> {
  late final DialService _dialService = DialService(widget.ble);
  double _uploadProgress = 0.0;
  bool _isUploading = false;

  void _showNotificationDialog() {
    final title = TextEditingController(text: "WhatsApp");
    final body = TextEditingController(text: "Hello from HT99 Companion!");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Push Notification"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: title,
                decoration: const InputDecoration(labelText: "App Name")),
            const SizedBox(height: 8),
            TextField(
                controller: body,
                decoration: const InputDecoration(labelText: "Message Body")),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              widget.ble.pushNotification(title.text, body.text);
              Navigator.pop(ctx);
            },
            child: const Text("Send"),
          ),
        ],
      ),
    );
  }

  void _showWeatherDialog() {
    final tempCtrl = TextEditingController(text: "31");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Sync Weather"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: tempCtrl,
                decoration:
                    const InputDecoration(labelText: "Temperature (°C)")),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              int t = int.tryParse(tempCtrl.text) ?? 31;
              widget.ble.pushWeather(t, 1, t + 4, t - 4);
              Navigator.pop(ctx);
            },
            child: const Text("Sync"),
          ),
        ],
      ),
    );
  }

  void _showDialModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("320x385 Custom Dials",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (_isUploading) ...[
                LinearProgressIndicator(
                    value: _uploadProgress, color: const Color(0xFFFF5722)),
                const SizedBox(height: 8),
                Text("${(_uploadProgress * 100).toInt()}% Uploaded"),
              ] else
                ElevatedButton.icon(
                  onPressed: () async {
                    setModalState(() => _isUploading = true);
                    List<int> sampleDat = List.filled(400, 0x1A);
                    await _dialService.sendDialDat(sampleDat, (p) {
                      setModalState(() => _uploadProgress = p);
                    });
                    setModalState(() => _isUploading = false);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text("Push Test Dial (320x385)"),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool connected = widget.ble.device != null;

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
                          ? "Connected (${widget.ble.telemetry.batteryLevel}%)"
                          : "Disconnected",
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: connected
                    ? () => widget.ble.disconnect()
                    : widget.onConnectTrigger,
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
              SwitchListTile(
                secondary: const CircleAvatar(
                  backgroundColor: Color(0x226C5CE7),
                  child:
                      Icon(Icons.access_time_filled, color: Color(0xFF6C5CE7)),
                ),
                title: const Text("12-Hour Format"),
                subtitle: Text(widget.ble.telemetry.is12Hour
                    ? "AM/PM Mode"
                    : "24-Hour Mode"),
                value: widget.ble.telemetry.is12Hour,
                onChanged: connected ? (v) => widget.ble.syncClock(v) : null,
              ),
              const Divider(height: 1, indent: 64),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0x22FFA502),
                  child: Icon(Icons.vibration, color: Color(0xFFFFA502)),
                ),
                title: const Text("Find Bracelet"),
                subtitle: const Text("Triggers Immediate Alert"),
                trailing: const Icon(Icons.chevron_right),
                onTap: connected ? () => widget.ble.ringWatch() : null,
              ),
              const Divider(height: 1, indent: 64),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0x2200E5FF),
                  child: Icon(Icons.notifications_active,
                      color: Color(0xFF00E5FF)),
                ),
                title: const Text("Push Notification"),
                subtitle: const Text("Send structured XML text"),
                trailing: const Icon(Icons.chevron_right),
                onTap: connected ? _showNotificationDialog : null,
              ),
              const Divider(height: 1, indent: 64),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0x222ECC71),
                  child: Icon(Icons.cloud_sync, color: Color(0xFF2ECC71)),
                ),
                title: const Text("Sync Weather"),
                subtitle: const Text("Update temperatures and forecast"),
                trailing: const Icon(Icons.chevron_right),
                onTap: connected ? _showWeatherDialog : null,
              ),
              const Divider(height: 1, indent: 64),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0x229C27B0),
                  child: Icon(Icons.wallpaper, color: Color(0xFF9C27B0)),
                ),
                title: const Text("Dial Push"),
                subtitle: const Text("Upload 320x385 watch face"),
                trailing: const Icon(Icons.chevron_right),
                onTap: connected ? _showDialModal : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
