import 'package:flutter/material.dart';

class SosScreen extends StatelessWidget {
  const SosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff071B52),
      appBar: AppBar(
        backgroundColor: const Color(0xff071B52),
        title: const Text("SOS"),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            const Icon(
              Icons.warning_rounded,
              color: Colors.red,
              size: 90,
            ),

            const SizedBox(height: 20),

            const Text(
              "Emergency SOS",
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 15),

            const Text(
              "SOS Feature Coming Soon",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 18,
              ),
            ),

            const SizedBox(height: 40),

            ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("SOS Module will be added later."),
                  ),
                );
              },
              child: const Text("Test SOS"),
            ),
          ],
        ),
      ),
    );
  }
}