import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'services/accident_detection_service.dart';
import 'services/incident_alert_bridge.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await AppSettings.load();
  AccidentDetectionService.init();

  runApp(const SafeCityApp());

  // Pop-up incident alerts even when the app is closed (native service).
  IncidentAlertBridge.init();
}

class SafeCityApp extends StatelessWidget {
  const SafeCityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: AccidentDetectionService.navigatorKey,
      title: 'SafeCity',

      theme: ThemeData(
  useMaterial3: true,

  primaryColor: const Color(0xFF0A2E73),

  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF0A2E73),
  ),

  scaffoldBackgroundColor: Colors.white,

  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF0A2E73),
    foregroundColor: Colors.white,
    elevation: 0,
  ),
),
      home: const SplashScreen(),
    );
  }
}