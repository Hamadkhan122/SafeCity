// SafeCity - App settings (stored on the phone via the native
// "safecity/prefs" channel in MainActivity.kt -> Android SharedPreferences)
// =====================================================
// Each setting is a ValueNotifier, so screens/services rebuild or react
// as soon as it changes (e.g. accident detection starts/stops instantly).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppSettings {
  AppSettings._();

  static const sensitivityLabels = ["Low", "Medium", "High"];

  /// Accident detection (phone motion sensor) on/off.
  static final accidentDetection = ValueNotifier<bool>(false);

  /// 0 = Low (less reactive), 1 = Medium, 2 = High (more reactive).
  static final sensitivity = ValueNotifier<int>(1);

  /// Seconds the "Are you OK?" countdown waits before sending SOS.
  static final sosCountdown = ValueNotifier<int>(15);

  /// Share live location inside the emergency chat.
  static final liveLocationSharing = ValueNotifier<bool>(true);

  /// Show in-app banners for newly reported incidents.
  static final incidentAlerts = ValueNotifier<bool>(true);

  static const _channel = MethodChannel("safecity/prefs");

  static Future<void> load() async {
    try {
      final m = Map<String, dynamic>.from(
          await _channel.invokeMethod<Map>("getAll") ?? const {});
      bool b(String k, bool d) => m[k] is bool ? m[k] as bool : d;
      int i(String k, int d) => m[k] is int ? m[k] as int : d;
      accidentDetection.value = b("accidentDetection", false);
      sensitivity.value = i("sensitivity", 1).clamp(0, 2).toInt();
      sosCountdown.value = i("sosCountdown", 15);
      liveLocationSharing.value = b("liveLocationSharing", true);
      incidentAlerts.value = b("incidentAlerts", true);
    } catch (e) {
      debugPrint("Settings load error: $e");
    }
  }

  static Future<void> _setBool(String key, bool value) async {
    try {
      await _channel.invokeMethod("setBool", {"key": key, "value": value});
    } catch (e) {
      debugPrint("Settings save error: $e");
    }
  }

  static Future<void> _setInt(String key, int value) async {
    try {
      await _channel.invokeMethod("setInt", {"key": key, "value": value});
    } catch (e) {
      debugPrint("Settings save error: $e");
    }
  }

  static Future<void> setAccidentDetection(bool v) async {
    accidentDetection.value = v;
    await _setBool("accidentDetection", v);
  }

  static Future<void> setSensitivity(int v) async {
    sensitivity.value = v;
    await _setInt("sensitivity", v);
  }

  static Future<void> setSosCountdown(int v) async {
    sosCountdown.value = v;
    await _setInt("sosCountdown", v);
  }

  static Future<void> setLiveLocationSharing(bool v) async {
    liveLocationSharing.value = v;
    await _setBool("liveLocationSharing", v);
  }

  static Future<void> setIncidentAlerts(bool v) async {
    incidentAlerts.value = v;
    await _setBool("incidentAlerts", v);
  }
}
