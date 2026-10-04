// SafeCity - Incident alerts when the app is closed (Dart side)
// ==============================================================
// Turns the native IncidentAlertService (IncidentAlertService.kt) on/off
// following Settings -> Incident Alerts. The service listens to new
// incident notifications in Firestore and pops up a notification on the
// phone screen (like a WhatsApp message) for incidents within 10 km,
// even when SafeCity is closed. Free: no server or FCM needed.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'settings_service.dart';

class IncidentAlertBridge {
  IncidentAlertBridge._();

  static const _channel = MethodChannel("safecity/alerts");

  static void init() {
    AppSettings.incidentAlerts.addListener(_sync);
    _sync();
  }

  static Future<void> _sync() async {
    try {
      await _channel
          .invokeMethod(AppSettings.incidentAlerts.value ? "start" : "stop");
    } catch (e) {
      debugPrint("Incident alert service error: $e");
    }
  }
}
