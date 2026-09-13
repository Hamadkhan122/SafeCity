import 'dart:async';
import 'package:flutter/material.dart';
import '../models/notification_model.dart';

class NotificationBanner extends StatefulWidget {
  final NotificationModel notification;
  final VoidCallback onView;
  final VoidCallback onDismiss;

  const NotificationBanner({
    super.key,
    required this.notification,
    required this.onView,
    required this.onDismiss,
  });

  @override
  State<NotificationBanner> createState() => _NotificationBannerState();
}

class _NotificationBannerState extends State<NotificationBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), widget.onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Color _categoryColor() {
    switch (widget.notification.category) {
      case "Accident":
        return Colors.red;
      case "Fire":
        return Colors.orange;
      case "Theft":
        return Colors.purpleAccent;
      case "Road Damage":
        return Colors.green;
      case "Fight":
        return Colors.deepOrange;
      case "Harassment":
        return Colors.pinkAccent;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor();

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xff10245c),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(.2),
              child: Icon(Icons.warning_amber_rounded, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "🚨 ${widget.notification.title}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.notification.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: widget.onView,
                        child: const Text(
                          "View",
                          style: TextStyle(
                            color: Color(0xff66BB6A),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: widget.onDismiss,
                        child: const Text(
                          "Dismiss",
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}