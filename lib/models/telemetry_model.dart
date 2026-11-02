class HeartRateRecord {
  final int bpm;
  final String time;

  HeartRateRecord({required this.bpm, required this.time});
}

class WatchAlarm {
  int hour;
  int minute;
  List<bool> days; // Sunday to Saturday (7 elements)
  bool isEnabled;

  WatchAlarm({
    required this.hour,
    required this.minute,
    required this.days,
    this.isEnabled = true,
  });

  String get formattedTime =>
      "${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}";

  int get repeatMask {
    int mask = 0;
    for (int i = 0; i < days.length && i < 7; i++) {
      if (days[i]) mask |= (1 << i);
    }
    return mask == 0 ? 127 : mask;
  }
}

class TelemetryModel {
  int steps;
  int calories;
  double distanceKm;
  int heartRate;
  int batteryLevel; // -1 represents loading state to prevent initial 25% glitch
  int systolicBp;
  int diastolicBp;
  double bodyTemp;
  int immunity;
  double sleepHours;
  bool is12Hour;

  final List<HeartRateRecord> hrHistory = [];
  final List<WatchAlarm> alarms = [];
  int drinkWaterIntervalMinutes = 60;
  bool isDrinkWaterEnabled = false;

  TelemetryModel({
    this.steps = 0,
    this.calories = 0,
    this.distanceKm = 0.0,
    this.heartRate = 0,
    this.batteryLevel = -1,
    this.systolicBp = 0,
    this.diastolicBp = 0,
    this.bodyTemp = 0.0,
    this.immunity = 0,
    this.sleepHours = 0.0,
    this.is12Hour = true,
  });
}
