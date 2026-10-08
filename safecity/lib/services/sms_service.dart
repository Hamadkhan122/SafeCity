// SafeCity - SOS SMS (works even if the emergency contact has no app
// and no internet)
// ======================================================================
// 1. SOS pressed      -> SMS sent automatically with a Google Maps link
// 2. Every 5 minutes  -> location update SMS (max 6), until "I'm safe"
// 3. "I'm safe"       -> "I'm safe now" SMS
//
// SMS is sent natively (android MainActivity "safecity/sms", SEND_SMS
// permission). If the user denies the permission, send() returns false and
// the caller falls back to opening the messaging app.
// Texts are plain English without emoji so each SMS stays a normal
// 160-character message (cheaper than Unicode SMS).

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

class SmsService {
  SmsService._();

  static const _channel = MethodChannel('safecity/sms');

  static const Duration updateEvery = Duration(minutes: 5);
  static const int maxUpdates = 6;

  static Timer? _timer;
  static String? _trackingChatId;
  static String? _trackingPhone;
  static String _trackingName = "Your contact";
  static int _sent = 0;

  static String mapsLink(double lat, double lng) =>
      "https://maps.google.com/?q=${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}";

  /// Sends an SMS directly. Returns false if not possible (permission
  /// denied, no SIM, ...).
  static Future<bool> send(String number, String text) async {
    try {
      final ok = await _channel
          .invokeMethod<bool>('sendSms', {'number': number, 'text': text});
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static String sosText(String name, String reason, double lat, double lng) =>
      "EMERGENCY! $name needs help"
      "${reason == "I need help" || reason == "SOS" ? "" : ": $reason"}. "
      "Live location: ${mapsLink(lat, lng)} "
      "Please call now. Location updates will follow. - SafeCity";

  /// Starts the 5-minute location update SMS for an active SOS.
  static void startLocationUpdates({
    required String chatId,
    required String phone,
    required String name,
  }) {
    if (_trackingChatId == chatId && _timer != null) return;
    stopLocationUpdates();
    _trackingChatId = chatId;
    _trackingPhone = phone;
    _trackingName = name;
    _sent = 0;
    _timer = Timer.periodic(updateEvery, (_) => _sendUpdate());
  }

  static Future<void> _sendUpdate() async {
    final phone = _trackingPhone;
    if (phone == null || _sent >= maxUpdates) {
      stopLocationUpdates();
      return;
    }
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      _sent++;
      await send(
        phone,
        "SafeCity update $_sent/$maxUpdates: $_trackingName is still in "
        "SOS. Current location: ${mapsLink(p.latitude, p.longitude)}",
      );
    } catch (_) {
      // No location right now - try again at the next tick.
    }
  }

  static void stopLocationUpdates() {
    _timer?.cancel();
    _timer = null;
    _trackingChatId = null;
    _trackingPhone = null;
  }

  /// "I'm safe" -> stop updates and tell the contact.
  static Future<void> sendSafe(String? phone, String name) async {
    final number = phone ?? _trackingPhone;
    stopLocationUpdates();
    if (number == null || number.trim().isEmpty) return;
    await send(number, "$name is SAFE now. The SOS has ended. - SafeCity");
  }
}
