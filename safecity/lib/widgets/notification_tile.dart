import 'package:flutter/material.dart';
import '../models/notification_model.dart';

class NotificationTile extends StatelessWidget {
  final NotificationModel notification;
  final double? distanceMeters;
  final VoidCallback onTap;

  const NotificationTile({
    super.key,
    required this.notification,
    required this.distanceMeters,
    required this.onTap,
  });

  Color _categoryColor() {
    switch (notification.category) {
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

  IconData _categoryIcon() {
    switch (notification.category) {
      case "Accident":
        return Icons.car_crash;
      case "Fire":
        return Icons.local_fire_department;
      case "Theft":
        return Icons.report;
      case "Road Damage":
        return Icons.construction;
      case "Fight":
        return Icons.front_hand;
      case "Harassment":
        return Icons.person_off;
      default:
        return Icons.warning;
    }
  }

  String _timeAgo() {
    final dt = notification.createdAt;
    if (dt == null) return "";

    final diff = DateTime.now().difference(dt);

    if (diff.inSeconds < 45) return "Now";
    if (diff.inMinutes < 60) return "${diff.inMinutes} min ago";
    if (diff.inHours < 24) return "${diff.inHours} hr ago";
    if (diff.inDays == 1) return "Yesterday";
    if (diff.inDays < 7) return "${diff.inDays} days ago";

    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    return "${dt.day} ${months[dt.month - 1]} ${dt.year}";
  }

  String _distanceText() {
    if (distanceMeters == null) return "";
    if (distanceMeters! < 1000) {
      return "${distanceMeters!.toStringAsFixed(0)} m away";
    }
    return "${(distanceMeters! / 1000).toStringAsFixed(1)} KM away";
  }

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notification.isRead
              ? Colors.white.withOpacity(.05)
              : Colors.white.withOpacity(.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: notification.isRead
                ? Colors.white12
                : color.withOpacity(0.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  backgroundColor: color.withOpacity(.2),
                  child: Icon(_categoryIcon(), color: color),
                ),
                if (!notification.isRead)
                  Positioned(
                    right: -1,
                    top: -1,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xff071B52),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.message,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (distanceMeters != null) ...[
                        const Icon(
                          Icons.location_on,
                          size: 12,
                          color: Colors.orangeAccent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _distanceText(),
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      const Icon(
                        Icons.access_time,
                        size: 12,
                        color: Colors.white38,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _timeAgo(),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
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