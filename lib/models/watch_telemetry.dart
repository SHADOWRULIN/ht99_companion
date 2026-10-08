class WatchTelemetry {
  int batteryLevel;
  int steps;
  int calories;
  double distanceKm;
  int heartRate;
  bool is12HourFormat;

  WatchTelemetry({
    this.batteryLevel = 50,
    this.steps = 0,
    this.calories = 0,
    this.distanceKm = 0.0,
    this.heartRate = 0,
    this.is12HourFormat = true,
  });
}
