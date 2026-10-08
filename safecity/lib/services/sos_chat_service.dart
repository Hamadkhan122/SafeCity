// SafeCity - Emergency Live Chat (inside the app)
// =====================================================
// Firestore:
//   sos_chats/{chatId}
//     ownerId, ownerName, ownerPhone      -> person who pressed SOS
//     contactUid, contactName, contactPhone -> emergency contact
//     participants: [ownerId, contactUid?]
//     active, reason, alertId, latitude, longitude, locationUpdatedAt,
//     createdAt, endedAt
//   sos_chats/{chatId}/messages/{id}
//     senderId, senderName, text, type (text | location | alert | system),
//     latitude?, longitude?, createdAt
//
// The emergency contact joins the chat automatically if they also use
// SafeCity (matched by phone number). They see a red "needs help" banner
// on their Home screen and can reply in real time.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SosChatService {
  SosChatService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get chats =>
      _db.collection("sos_chats");

  /// Last 10 digits, so 0300-1234567 and +92 300 1234567 match.
  static String phoneKey(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    return d.length > 10 ? d.substring(d.length - 10) : d;
  }

  /// SafeCity user whose phone matches [phone], or null.
  static Future<String?> findUserByPhone(String phone) async {
    final key = phoneKey(phone);
    if (key.length < 7) return null;
    final me = FirebaseAuth.instance.currentUser?.uid;
    try {
      // Own number saved as emergency contact -> no other person to chat with.
      final q = await _db
          .collection("users")
          .where("phoneKey", isEqualTo: key)
          .get();
      for (final d in q.docs) {
        if (d.id != me) return d.id;
      }

      // Older accounts saved before "phoneKey" existed.
      final all = await _db.collection("users").get();
      for (final d in all.docs) {
        if (d.id == me) continue;
        if (phoneKey((d.data()["phone"] ?? "").toString()) == key) return d.id;
      }
    } catch (_) {}
    return null;
  }

  /// The current user's own active chat (if any).
  /// If the emergency contact was changed since that chat started, the old
  /// chat is closed and null is returned, so a NEW chat with the new
  /// contact is created.
  static Future<String?> activeChatId() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final q = await chats.where("ownerId", isEqualTo: uid).get();

    String currentKey = "";
    try {
      final u = await _db.collection("users").doc(uid).get();
      final c = u.data()?["emergency_contact"];
      if (c is Map) currentKey = phoneKey((c["phone"] ?? "").toString());
    } catch (_) {}

    for (final d in q.docs) {
      final c = d.data();
      if (c["active"] != true) continue;
      final chatKey = phoneKey((c["contactPhone"] ?? "").toString());
      if (currentKey.isNotEmpty && chatKey != currentKey) {
        await endChat(d.id,
            text: "Emergency contact changed — this chat was closed.");
        continue;
      }
      // Contact joined SafeCity after the chat started -> add them now.
      if (c["contactUid"] == null && c["contactPhone"] != null) {
        final cu = await findUserByPhone(c["contactPhone"].toString());
        if (cu != null) {
          await chats.doc(d.id).update({
            "contactUid": cu,
            "participants": FieldValue.arrayUnion([cu]),
          });
        }
      }
      return d.id;
    }
    return null;
  }

  /// Creates (or reuses) the user's emergency chat.
  static Future<String> startChat({
    required double latitude,
    required double longitude,
    String? contactName,
    String? contactPhone,
    String? alertId,
    String reason = "SOS",
  }) async {
    final me = FirebaseAuth.instance.currentUser!;
    final existing = await activeChatId();
    if (existing != null) {
      await updateLocation(existing, latitude, longitude);
      return existing;
    }

    final userDoc = await _db.collection("users").doc(me.uid).get();
    final u = userDoc.data() ?? {};
    final myName = (u["fullName"] ?? me.email ?? "SafeCity user").toString();
    final contactUid =
        contactPhone == null ? null : await findUserByPhone(contactPhone);

    final ref = chats.doc();
    await ref.set({
      "chatId": ref.id,
      "ownerId": me.uid,
      "ownerName": myName,
      "ownerPhone": (u["phone"] ?? "").toString(),
      "contactUid": contactUid,
      "contactName": contactName,
      "contactPhone": contactPhone,
      "participants": [me.uid, if (contactUid != null) contactUid],
      "active": true,
      "reason": reason,
      "alertId": alertId,
      "latitude": latitude,
      "longitude": longitude,
      "locationUpdatedAt": FieldValue.serverTimestamp(),
      "createdAt": FieldValue.serverTimestamp(),
    });

    await sendMessage(
      ref.id,
      text: "🚨 $reason — I need help! My live location is shared in this chat.",
      type: "alert",
      latitude: latitude,
      longitude: longitude,
    );
    if (contactUid == null) {
      await sendMessage(
        ref.id,
        text: "${contactName ?? "Your contact"} is not on SafeCity yet, so "
            "they received your SMS instead. Use the helplines above if needed.",
        type: "system",
      );
    }
    return ref.id;
  }

  /// Active chats where the current user is owner or contact.
  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> myActiveChats(
      String uid) {
    return chats.where("participants", arrayContains: uid).snapshots().map(
          (s) => s.docs.where((d) => d.data()["active"] == true).toList(),
        );
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> chat(String chatId) =>
      chats.doc(chatId).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> messages(String chatId) =>
      chats
          .doc(chatId)
          .collection("messages")
          .orderBy("createdAt", descending: true)
          .limit(200)
          .snapshots();

  static Future<void> sendMessage(
    String chatId, {
    required String text,
    String type = "text",
    double? latitude,
    double? longitude,
    bool urgent = false,
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    String name = me?.email ?? "SafeCity user";
    try {
      final u = await _db.collection("users").doc(me?.uid).get();
      final n = (u.data()?["fullName"] ?? "").toString().trim();
      if (n.isNotEmpty) name = n;
    } catch (_) {}

    await chats.doc(chatId).collection("messages").add({
      "senderId": type == "system" ? "system" : me?.uid,
      "senderName": type == "system" ? "SafeCity" : name,
      "text": text,
      "type": type,
      if (latitude != null) "latitude": latitude,
      if (longitude != null) "longitude": longitude,
      if (urgent) "urgent": true,
      "createdAt": FieldValue.serverTimestamp(),
    });
    await chats.doc(chatId).update({
      "lastMessage": text,
      "lastMessageAt": FieldValue.serverTimestamp(),
    });
  }

  static Future<void> updateLocation(String chatId, double lat, double lng) =>
      chats.doc(chatId).update({
        "latitude": lat,
        "longitude": lng,
        "locationUpdatedAt": FieldValue.serverTimestamp(),
      });

  static Future<void> endChat(String chatId,
      {String text = "SOS ended — the user marked themselves safe."}) async {
    await sendMessage(chatId, text: text, type: "system");
    await chats.doc(chatId).update({
      "active": false,
      "endedAt": FieldValue.serverTimestamp(),
    });
  }
}
