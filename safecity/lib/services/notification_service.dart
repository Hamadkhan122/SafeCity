import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification_model.dart';

/// Currently backed entirely by Firestore realtime listeners.
///
/// When push notifications (FCM) are added later, only the internals of
/// this class need to change (e.g. writing an FCM payload alongside the
/// Firestore doc, or listening to FCM foreground messages). Screens and
/// widgets only ever talk to this service — never to Firestore directly —
/// so no UI code will need to change.
class NotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _collection =>
      _firestore.collection("notifications");

  /// Full realtime list, newest first.
  Stream<List<NotificationModel>> notificationsStream() {
    return _collection.orderBy("createdAt", descending: true).snapshots().map(
      (snapshot) =>
          snapshot.docs.map((doc) => NotificationModel.fromDoc(doc)).toList(),
    );
  }

  /// Unread count — drives the bell badge.
  Stream<int> unreadCountStream() {
    return _collection
        .where("isRead", isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Latest single notification — drives the home screen banner.
  Stream<NotificationModel?> latestNotificationStream() {
    return _collection
        .orderBy("createdAt", descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return null;
          return NotificationModel.fromDoc(snapshot.docs.first);
        });
  }

  Future<void> markAsRead(String id) async {
    try {
      await _collection.doc(id).update({"isRead": true});
    } catch (e) {
      // Non-critical — ignore silently so a stale badge never blocks the UI.
    }
  }

  /// Called by ReportScreen when a new incident is submitted.
  Future<void> createNotification({
    required String title,
    required String message,
    required String category,
    required double latitude,
    required double longitude,
  }) async {
    await _collection.add({
      "title": title,
      "message": message,
      "category": category,
      "latitude": latitude,
      "longitude": longitude,
      "createdAt": FieldValue.serverTimestamp(),
      "isRead": false,
    });
  }
}