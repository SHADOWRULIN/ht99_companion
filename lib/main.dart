import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'services/watch_ble_service.dart';
import 'ui/home_tab.dart';
import 'ui/device_tab.dart';
import 'ui/my_tab.dart';
import 'ui/terminal_tab.dart';

void main() {
  runApp(const Ht99MasterApp());
}

class Ht99MasterApp extends StatefulWidget {
  const Ht99MasterApp({super.key});

  @override
  State<Ht99MasterApp> createState() => _Ht99MasterAppState();
}

class _Ht99MasterAppState extends State<Ht99MasterApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  final WatchBleService _ble = WatchBleService();

  int _currentIndex = 0;
  int _stepGoal = 10000;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;

  @override
  void initState() {
    super.initState();
    _ble.onData = () => setState(() {});

    FlutterBluePlus.adapterState.listen((state) {
      setState(() => _adapterState = state);
    });

    _ble.onFindPhoneTriggered = () {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2C),
            title: const Row(
              children: [
                Icon(Icons.ring_volume_rounded,
                    color: Color(0xFFFF5722), size: 30),
                SizedBox(width: 10),
                Text("Watch Finding Phone!"),
              ],
            ),
            content: const Text(
                "Your HT99 watch is triggering this phone to ring and vibrate."),
            actions: [
              ElevatedButton(
                onPressed: () {
                  _ble.stopFindPhoneAlarm();
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5722),
                    foregroundColor: Colors.white),
                child: const Text("Stop Ringing"),
              ),
            ],
          ),
        );
      }
    };
  }

  void _showScanModal() {
    if (_ble.isConnecting || _ble.isConnected) return;
    _ble.scanAndConnect();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Connecting to HT99", textAlign: TextAlign.center),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFFF5722)),
            SizedBox(height: 16),
            Text("Negotiating link & handshake...",
                textAlign: TextAlign.center),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceAround,
        actions: [
          TextButton(
            onPressed: () {
              _ble.stopScan();
              _ble.isConnecting = false;
              Navigator.pop(ctx);
            },
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              _ble.stopScan();
              _ble.isConnecting = false;
              _ble.scanAndConnect();
            },
            child: const Text("Search Again"),
          ),
        ],
      ),
    );

    _ble.onConnected = () {
      if (Navigator.canPop(context)) Navigator.pop(context);
    };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "HT99 Manager Pro",
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF6F8FB),
        cardColor: Colors.white,
        colorScheme: const ColorScheme.light(primary: Color(0xFFFF5722)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0F15),
        cardColor: const Color(0xFF161922),
        colorScheme: const ColorScheme.dark(primary: Color(0xFFFF5722)),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              if (_adapterState != BluetoothAdapterState.on &&
                  _adapterState != BluetoothAdapterState.unknown)
                Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.redAccent),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bluetooth_disabled,
                          color: Colors.redAccent),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text("Bluetooth is turned off.",
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      ElevatedButton(
                        onPressed: () => FlutterBluePlus.turnOn(),
                        child: const Text("Turn On"),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: _currentIndex,
                  children: [
                    HomeTab(ble: _ble, stepGoal: _stepGoal),
                    DeviceTab(ble: _ble, onConnectTrigger: _showScanModal),
                    MyTab(
                      currentTheme: _themeMode,
                      onThemeChange: (m) => setState(() => _themeMode = m),
                      stepGoal: _stepGoal,
                      onGoalChange: (g) => setState(() => _stepGoal = g),
                    ),
                    TerminalTab(ble: _ble),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_rounded), label: "Home"),
            NavigationDestination(
                icon: Icon(Icons.watch_rounded), label: "Device"),
            NavigationDestination(
                icon: Icon(Icons.person_rounded), label: "My"),
            NavigationDestination(
                icon: Icon(Icons.terminal_rounded), label: "Terminal"),
          ],
        ),
      ),
    );
  }
}
