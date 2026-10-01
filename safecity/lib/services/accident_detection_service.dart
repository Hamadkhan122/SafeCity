// SafeCity - Accident Detection (phone motion sensor)
// =====================================================
// While the app is open and the setting is ON, the accelerometer is read
// ~50 times per second (native "safecity/accel" channel in MainActivity.kt). A sudden impact (acceleration above the threshold
// for the chosen sensitivity, gravity excluded) opens an "Are you OK?"
// countdown. If the user does not answer, SOS is sent automatically.
//
//   Sensitivity  Low  -> 4.0 g  (only hard impacts)
//                Medium -> 3.0 g
//                High -> 2.2 g  (more reactive)
// After a trigger, detection pauses for 60 s to avoid repeated alerts.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/sos_screen.dart';
import 'settings_service.dart';

class AccidentDetectionService {
  AccidentDetectionService._();

  /// Used to show the countdown from anywhere in the app.
  static final navigatorKey = GlobalKey<NavigatorState>();

  static const List<double> thresholdsG = [4.0, 3.0, 2.2];
  static const int cooldownSeconds = 60;

  static const _accel = EventChannel("safecity/accel");
  static StreamSubscription<dynamic>? _sub;
  static DateTime _lastTrigger = DateTime(2000);
  static bool _dialogOpen = false;

  static void init() {
    AppSettings.accidentDetection.addListener(_sync);
    _sync();
  }

  static void _sync() {
    if (AppSettings.accidentDetection.value) {
      _start();
    } else {
      _stop();
    }
  }

  static void _start() {
    _sub ??= _accel.receiveBroadcastStream().listen(
      _onEvent,
      onError: (e) => debugPrint("Accelerometer error: $e"),
      cancelOnError: false,
    );
  }

  static void _stop() {
    _sub?.cancel();
    _sub = null;
  }

  static void _onEvent(dynamic value) {
    if (value is! num) return;
    final g = value.toDouble() / 9.81; // m/s^2 -> g
    if (g < thresholdsG[AppSettings.sensitivity.value]) return;
    if (_dialogOpen) return;
    if (DateTime.now().difference(_lastTrigger).inSeconds < cooldownSeconds) {
      return;
    }
    _lastTrigger = DateTime.now();
    showCheck();
  }

  /// Shows the countdown. Also used by "Test accident alert" in Settings.
  static Future<void> showCheck({bool test = false}) async {
    final nav = navigatorKey.currentState;
    final ctx = nav?.overlay?.context;
    if (nav == null || ctx == null || _dialogOpen) return;

    _dialogOpen = true;
    final sendSos = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _AccidentCountdownDialog(
        seconds: AppSettings.sosCountdown.value,
        test: test,
      ),
    );
    _dialogOpen = false;

    if (sendSos == true) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => const SosScreen(
            autoSend: true,
            reason: "Possible accident detected",
          ),
        ),
      );
    }
  }
}

class _AccidentCountdownDialog extends StatefulWidget {
  final int seconds;
  final bool test;
  const _AccidentCountdownDialog({required this.seconds, required this.test});

  @override
  State<_AccidentCountdownDialog> createState() =>
      _AccidentCountdownDialogState();
}

class _AccidentCountdownDialogState extends State<_AccidentCountdownDialog> {
  late int _left = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_left <= 1) {
        t.cancel();
        Navigator.pop(context, true);
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Column(
        children: [
          const Icon(Icons.car_crash, color: Color(0xffD32F2F), size: 46),
          const SizedBox(height: 8),
          Text(
            widget.test ? "Test: Accident detected" : "Accident detected?",
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "We noticed a sudden impact. If you don't respond, an SOS with "
            "your live location will be sent to your emergency contact.",
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 86,
            height: 86,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 86,
                  height: 86,
                  child: CircularProgressIndicator(
                    value: _left / widget.seconds,
                    strokeWidth: 7,
                    backgroundColor: Colors.red.shade50,
                    valueColor:
                        const AlwaysStoppedAnimation(Color(0xffD32F2F)),
                  ),
                ),
                Text(
                  "$_left",
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Color(0xffD32F2F),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceEvenly,
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context, false),
          child: const Text("I'm OK"),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xffD32F2F),
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text("Send SOS now"),
        ),
      ],
    );
  }
}
