// SafeCity - Route Test tools (fake scenarios for testing / demo)
// ===============================================================
// Committee: "You can test with fake scenarios." These tools let the team
// test Safe Route Suggestion WITHOUT a real incident and without driving:
//
//   1. Fake incident ON the current route (e.g. 400 m ahead) or at any
//      point on the map (long-press in Test Mode).
//   2. Drive simulator: moves "you" along the selected route at 40 km/h,
//      so the live re-routing can be shown sitting in the class room.
//   3. "Mark cleared": a test incident is answered "cleared" so the place
//      turns safe again (same voting as real incidents).
//
// Test incidents are normal reports with isTest = true and status
// "Verified" (skipping AIVE, because there is no real photo). They:
//   - show "[TEST]" in the description,
//   - are ignored by AIVE (duplicate / spam / nearby checks),
//   - end by themselves after 2 hours (IncidentStatusService.testWindow).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'incident_status_service.dart';

class RouteTestService {
  RouteTestService._();

  static const List<String> categories = [
    "Accident",
    "Fire",
    "Fight",
    "Harassment",
    "Road Damage",
  ];

  /// Creates a fake verified incident. Returns its Firestore doc id.
  static Future<String> createTestIncident({
    required String category,
    required double lat,
    required double lng,
    String note = "",
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final ref = FirebaseFirestore.instance.collection("reports").doc();
    final id = "TEST-${DateTime.now().millisecondsSinceEpoch % 100000}";
    await ref.set({
      "reportId": id,
      "category": category,
      "description":
          "[TEST] Fake $category for Safe Route testing${note.isEmpty ? "" : " - $note"}",
      "latitude": lat,
      "longitude": lng,
      "address": "Test scenario",
      "gpsAccuracy": 5,
      "imageUrl": "",
      "status": "Verified",
      "confidence": 1.0,
      "isTest": true,
      "aive": {"version": 2, "flags": ["Test incident (created in Route Test mode)"]},
      "createdAt": FieldValue.serverTimestamp(),
      "userId": uid,
    });
    return ref.id;
  }

  /// "Cleared" answer from the creator -> the incident ends at once.
  static Future<void> clearTestIncident(String docId) =>
      IncidentStatusService.vote(docId, true);
}
