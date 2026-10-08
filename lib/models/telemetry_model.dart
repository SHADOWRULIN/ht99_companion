class TelemetryModel {
  int steps;
  int calories;
  double distanceKm;
  int heartRate;
  int batteryLevel;
  bool is12Hour;

  TelemetryModel({
    this.steps = 0,
    this.calories = 0,
    this.distanceKm = 0.0,
    this.heartRate = 0,
    this.batteryLevel = 50,
    this.is12Hour = true,
  });
}
