import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();

    _splashTimer = Timer(
      const Duration(seconds: 4),
      () {
        if (!context.mounted) return;

        final isLoggedIn = FirebaseAuth.instance.currentUser != null;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                isLoggedIn ? const HomeScreen() : const LoginScreen(),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      body: Stack(

        children: [

          //----------------------------------------
          // Background Gradient
          //----------------------------------------

          Container(

            decoration: const BoxDecoration(

              gradient: LinearGradient(

                begin: Alignment.topLeft,
                end: Alignment.bottomRight,

                colors: [

                  Color(0xff031B4E),

                  Color(0xff0A2E73),

                  Color(0xff0F4BA8),

                ],

              ),

            ),

          ),

          //----------------------------------------
          // Pakistan Map
          //----------------------------------------

          Positioned.fill(

            child: Opacity(

              opacity: .08,

              child: Image.asset(

                "assets/pakistan_map.png",

                fit: BoxFit.cover,

              ),

            ),

          ),

          //----------------------------------------
          // Top Glow
          //----------------------------------------

          Positioned(

            top: -120,
            right: -100,

            child: Container(

              height: 260,
              width: 260,

              decoration: BoxDecoration(

                color: Colors.lightBlueAccent.withOpacity(.12),

                shape: BoxShape.circle,

              ),

            ),

          ),

          //----------------------------------------
          // Bottom Glow
          //----------------------------------------

          Positioned(

            bottom: -140,
            left: -120,

            child: Container(

              height: 300,
              width: 300,

              decoration: BoxDecoration(

                color: Colors.greenAccent.withOpacity(.08),

                shape: BoxShape.circle,

              ),

            ),

          ),

          //----------------------------------------
          // Main Content
          //----------------------------------------

          SafeArea(

            child: Center(

              child: Padding(

                padding: const EdgeInsets.symmetric(horizontal: 30),

                child: Column(

                  mainAxisAlignment: MainAxisAlignment.center,

                  children: [

                    //----------------------------------
                    // Logo Card
                    //----------------------------------

                    Container(

                      height: 180,

                      width: 180,

                      decoration: BoxDecoration(

                        color: Colors.white.withOpacity(.12),

                        borderRadius: BorderRadius.circular(40),

                        border: Border.all(

                          color: Colors.white24,

                          width: 1.5,

                        ),

                        boxShadow: [

                          BoxShadow(

                            color: Colors.black.withOpacity(.25),

                            blurRadius: 30,

                            offset: const Offset(0, 20),

                          ),

                        ],

                      ),

                      child: Padding(

                        padding: const EdgeInsets.all(22),

                        child: Image.asset(

                          "assets/logo.png",

                          fit: BoxFit.contain,

                        ),

                      ),

                    ),

                    const SizedBox(height: 35),

                    //----------------------------------
                    // Title
                    //----------------------------------

                    const Text(

                      "SAFECITY",

                      style: TextStyle(

                        color: Colors.white,

                        fontSize: 42,

                        letterSpacing: 4,

                        fontWeight: FontWeight.w900,

                      ),

                    ),

                    const SizedBox(height: 12),

                    //----------------------------------
                    // Tagline
                    //----------------------------------

                    const Text(

                      "Protect • Report • Respond",

                      style: TextStyle(

                        color: Color(0xff7BE495),

                        fontSize: 18,

                        letterSpacing: 1.2,

                        fontWeight: FontWeight.w600,

                      ),

                    ),

                    const SizedBox(height: 10),

                    const Text(

                      "Building Safer Communities Through Technology",

                      textAlign: TextAlign.center,

                      style: TextStyle(

                        color: Colors.white70,

                        fontSize: 15,

                        height: 1.5,

                      ),

                    ),

                    const SizedBox(height: 55),

                    //----------------------------------
                    // Loading
                    //----------------------------------

                    SizedBox(

                      width: 45,

                      height: 45,

                      child: CircularProgressIndicator(

                        strokeWidth: 3,

                        color: Colors.greenAccent.shade400,

                      ),

                    ),

                    const SizedBox(height: 18),

                    const Text(

                      "Initializing Secure Services...",

                      style: TextStyle(

                        color: Colors.white70,

                        fontSize: 15,

                      ),

                    ),

                  ],

                ),

              ),

            ),

          ),

          //----------------------------------------
          // Bottom Skyline
          //----------------------------------------

          Positioned(

            bottom: 0,
            left: 0,
            right: 0,

            child: Container(

              height: 140,

              decoration: BoxDecoration(

                gradient: LinearGradient(

                  begin: Alignment.bottomCenter,

                  end: Alignment.topCenter,

                  colors: [

                    Colors.black.withOpacity(.55),

                    Colors.transparent,

                  ],

                ),

              ),

            ),

          ),

          //----------------------------------------
          // Bottom Text
          //----------------------------------------

          const Positioned(

            bottom: 28,

            left: 0,
            right: 0,

            child: Column(

              children: [

                Text(

                  "Powered by Firebase",

                  style: TextStyle(

                    color: Colors.white70,

                    fontWeight: FontWeight.w600,

                  ),

                ),

                SizedBox(height: 6),

                Text(

                  "Version 1.0.0",

                  style: TextStyle(

                    color: Colors.white38,

                  ),

                ),

              ],

            ),

          ),

        ],

      ),

    );

  }

}