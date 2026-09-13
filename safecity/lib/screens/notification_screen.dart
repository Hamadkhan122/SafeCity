import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../widgets/notification_tile.dart';
import 'map_screen.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final NotificationService notificationService = NotificationService();
  Position? currentPosition;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      currentPosition = await Geolocator.getCurrentPosition();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("notification location error: $e");
    }
  }

  double? _distanceTo(NotificationModel n) {
    if (currentPosition == null) return null;
    return Geolocator.distanceBetween(
      currentPosition!.latitude,
      currentPosition!.longitude,
      n.latitude,
      n.longitude,
    );
  }

  void _onTileTap(NotificationModel notification) {
    notificationService.markAsRead(notification.id);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          focusLat: notification.latitude,
          focusLng: notification.longitude,
          focusTitle: notification.title,
          focusSnippet: notification.message,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff071B52),
      appBar: AppBar(
        backgroundColor: const Color(0xff071B52),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Notifications",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<List<NotificationModel>>(
        stream: notificationService.notificationsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  "Couldn't load notifications.\n${snapshot.error}",
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return const Center(
              child: Text(
                "No Notifications",
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final n = notifications[index];
              return NotificationTile(
                notification: n,
                distanceMeters: _distanceTo(n),
                onTap: () => _onTileTap(n),
              );
            },
          );
        },
      ),
    );
  }
}