import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'services/watch_ble_service.dart';
import 'ui/home_tab.dart';
import 'ui/device_tab.dart';
import 'ui/my_tab.dart';
import 'ui/terminal_tab.dart';

void main() {
  runApp(const AppleWatchManagerApp());
}

// Neutral Earth Tones Palette
class EarthColors {
  static const Color ochreGold = Color(0xFFF5BE53);
  static const Color mutedSage = Color(0xFFC5D1CB);
  static const Color softCream = Color(0xFFEAEFE6);
  static const Color darkCharcoal = Color(0xFF202122);
  static const Color warmSlate = Color(0xFF2E3030);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color pureBlack = Color(0xFF000000);
}

class AppleWatchManagerApp extends StatefulWidget {
  const AppleWatchManagerApp({super.key});

  @override
  State<AppleWatchManagerApp> createState() => _AppleWatchManagerAppState();
}

class _AppleWatchManagerAppState extends State<AppleWatchManagerApp> {
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
            backgroundColor: EarthColors.warmSlate,
            title: const Row(
              children: [
                Icon(Icons.ring_volume_rounded,
                    color: EarthColors.ochreGold, size: 28),
                SizedBox(width: 10),
                Text("Watch Finding Phone",
                    style: TextStyle(color: Colors.white, fontSize: 18)),
              ],
            ),
            content: const Text(
              "Your HT99 watch is triggering this phone to ring and vibrate.",
              style: TextStyle(color: EarthColors.softCream),
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  _ble.stopFindPhoneAlarm();
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: EarthColors.ochreGold,
                  foregroundColor: EarthColors.pureBlack,
                ),
                child: const Text("Stop Alarm"),
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
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text("Connecting to Watch", textAlign: TextAlign.center),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 10),
            CircularProgressIndicator(color: EarthColors.ochreGold),
            SizedBox(height: 18),
            Text("Establishing link with HT99...",
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: EarthColors.ochreGold,
              foregroundColor: EarthColors.pureBlack,
            ),
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
      title: "Apple",
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,

      // Light Theme (Earth Tones: Cream, Sage, and Gold)
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: EarthColors.softCream,
        cardColor: EarthColors.pureWhite,
        colorScheme: const ColorScheme.light(
          primary: EarthColors.ochreGold,
          secondary: EarthColors.mutedSage,
          surface: EarthColors.pureWhite,
          onSurface: EarthColors.darkCharcoal,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: EarthColors.softCream,
          foregroundColor: EarthColors.darkCharcoal,
          elevation: 0,
        ),
        useMaterial3: true,
      ),

      // Dark Theme (Earth Tones: Charcoal, Slate, and Gold)
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: EarthColors.darkCharcoal,
        cardColor: EarthColors.warmSlate,
        colorScheme: const ColorScheme.dark(
          primary: EarthColors.ochreGold,
          secondary: EarthColors.mutedSage,
          surface: EarthColors.warmSlate,
          onSurface: EarthColors.softCream,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: EarthColors.darkCharcoal,
          foregroundColor: EarthColors.softCream,
          elevation: 0,
        ),
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
                    border:
                        Border.all(color: Colors.redAccent.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bluetooth_disabled,
                          color: Colors.redAccent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text("Bluetooth is turned off.",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      ElevatedButton(
                        onPressed: () => FlutterBluePlus.turnOn(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
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
          indicatorColor: EarthColors.ochreGold.withOpacity(0.25),
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
