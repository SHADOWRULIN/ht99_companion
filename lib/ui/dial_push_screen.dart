import 'package:flutter/material.dart';
import '../services/watch_ble_service.dart';
import '../services/dial_service.dart';

class DialPushScreen extends StatefulWidget {
  final WatchBleService ble;

  const DialPushScreen({super.key, required this.ble});

  @override
  State<DialPushScreen> createState() => _DialPushScreenState();
}

class _DialPushScreenState extends State<DialPushScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  late final DialService _dialService = DialService(widget.ble);
  double _uploadProgress = 0.0;
  bool _isUploading = false;

  final List<Map<String, dynamic>> presetDials = [
    {"name": "Earth 3D", "color": Colors.blueGrey},
    {"name": "Neon Chrono", "color": Colors.deepPurple},
    {"name": "Pastel Sphere", "color": Colors.pinkAccent},
    {"name": "Rainbow Sport", "color": Colors.amber},
    {"name": "Minimal Dark", "color": Colors.black54},
    {"name": "Roman Classic", "color": Colors.indigo},
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  void _pushDial() async {
    setState(() => _isUploading = true);

    // Pushes the genuine 320x385 MTK2502 binary instead of placeholder bytes
    bool success = await _dialService.pushPresetDial("assets/004012.dat", (p) {
      setState(() => _uploadProgress = p);
    });

    setState(() => _isUploading = false);
    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Watch face installed successfully!")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Dial push"),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFFF5BE53),
          tabs: const [
            Tab(text: "dial push"),
            Tab(text: "custom dial"),
          ],
        ),
      ),
      body: _isUploading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                      value: _uploadProgress, color: const Color(0xFFF5BE53)),
                  const SizedBox(height: 16),
                  Text(
                      "${(_uploadProgress * 100).toInt()}% Uploading dial to watch..."),
                ],
              ),
            )
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildPresetGrid(),
                _buildCustomDialTab(),
              ],
            ),
    );
  }

  Widget _buildPresetGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.7,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: presetDials.length,
      itemBuilder: (ctx, i) {
        var d = presetDials[i];
        return Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: d["color"],
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text("10:09",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 28,
              child: ElevatedButton(
                onPressed: widget.ble.isConnected ? _pushDial : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF5BE53),
                  foregroundColor: Colors.black,
                  padding: EdgeInsets.zero,
                ),
                child: const Text("SEND", style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCustomDialTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: Container(
            width: 140,
            height: 170,
            decoration: BoxDecoration(
              color: Colors.teal.shade800,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("08",
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                Text("30",
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        ListTile(
          title: const Text("Select the dial background"),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
          onTap: () {},
        ),
        const Divider(height: 1),
        ListTile(
          title: const Text("Dial type"),
          trailing: const Text("number", style: TextStyle(color: Colors.grey)),
          onTap: () {},
        ),
        const Divider(height: 1),
        ListTile(
          title: const Text("Dial position"),
          trailing:
              const Text("centered", style: TextStyle(color: Colors.grey)),
          onTap: () {},
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: widget.ble.isConnected ? _pushDial : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF5BE53),
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(48),
          ),
          child: const Text("Send"),
        ),
      ],
    );
  }
}
