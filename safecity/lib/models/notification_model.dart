import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;
  final String title;
  final String message;
  final String category;
  final double latitude;
  final double longitude;
  final DateTime? createdAt;
  final bool isRead;

  NotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    required this.isRead,
  });

  factory NotificationModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final ts = data["createdAt"] as Timestamp?;

    return NotificationModel(
      id: doc.id,
      title: data["title"]?.toString() ?? "Incident Reported",
      message: data["message"]?.toString() ?? "",
      category: data["category"]?.toString() ?? "Incident",
      latitude: (data["latitude"] as num?)?.toDouble() ?? 0,
      longitude: (data["longitude"] as num?)?.toDouble() ?? 0,
      createdAt: ts?.toDate(),
      isRead: data["isRead"] == true,
    );
  }
}