import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff071B52),

      appBar: AppBar(
        backgroundColor: const Color(0xff071B52),
        title: const Text("Profile"),
        centerTitle: true,
      ),

      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            const CircleAvatar(
              radius: 50,
              child: Icon(
                Icons.person,
                size: 60,
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              "User Profile",
              style: TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              "Profile Module Coming Soon",
              style: TextStyle(
                color: Colors.white70,
              ),
            ),

            const SizedBox(height: 40),

            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text("Back"),
            ),
          ],
        ),
      ),
    );
  }
}