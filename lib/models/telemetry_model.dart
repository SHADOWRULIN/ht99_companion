class HeartRateRecord {
  final int bpm;
  final String time;
  HeartRateRecord({required this.bpm, required this.time});
}

class WatchAlarm {
  int hour;
  int minute;
  List<bool> days; // Sunday through Saturday.
  bool isEnabled;
  WatchAlarm({
    required this.hour,
    required this.minute,
    required this.days,
    this.isEnabled = true,
  });
}

class TelemetryModel {
  int steps;
  int calories;
  double distanceKm;
  int heartRate;
  int batteryLevel;
  int systolicBp;
  int diastolicBp;
  double bodyTemp;
  int immunity;
  double sleepHours;
  bool is12Hour;
  int bloodOxygen;

  // Explicit validity flags stop placeholder defaults from looking like sensor data.
  bool hasStepData;
  bool hasCaloriesData;
  bool hasHeartRateData;
  bool hasBatteryData;
  bool hasBloodPressureData;
  bool hasTemperatureData;
  bool hasBloodOxygenData;

  final List<HeartRateRecord> hrHistory = <HeartRateRecord>[];
  final List<WatchAlarm> alarms = <WatchAlarm>[];
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
    this.bloodOxygen = -1,
    this.hasStepData = false,
    this.hasCaloriesData = false,
    this.hasHeartRateData = false,
    this.hasBatteryData = false,
    this.hasBloodPressureData = false,
    this.hasTemperatureData = false,
    this.hasBloodOxygenData = false,
  });
}
