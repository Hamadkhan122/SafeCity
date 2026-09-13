import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../screens/notification_screen.dart';

class NotificationBadge extends StatelessWidget {
  final NotificationService notificationService;

  const NotificationBadge({super.key, required this.notificationService});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: notificationService.unreadCountStream(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;

        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            );
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.notifications_none,
                  color: Colors.white,
                ),
              ),
              if (count > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      count > 9 ? "9+" : "$count",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}