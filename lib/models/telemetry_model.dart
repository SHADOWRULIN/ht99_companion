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

  TelemetryModel({
    this.steps = 0,
    this.calories = 0,
    this.distanceKm = 0.0,
    this.heartRate = 0,
    this.batteryLevel = 25,
    this.systolicBp = 0,
    this.diastolicBp = 0,
    this.bodyTemp = 0.0,
    this.immunity = 0,
    this.sleepHours = 0.0,
    this.is12Hour = true,
  });
}