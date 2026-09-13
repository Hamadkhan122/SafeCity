import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const SafeCityApp());
}

class SafeCityApp extends StatelessWidget {
  const SafeCityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
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