// SafeCity - Incident status: is an incident still ACTIVE or CLEARED?
// ===================================================================
// Committee requirement: when an incident is over (fire put out, accident
// cleared, road repaired) the app must show the place as safe again, at
// run time, without an admin.
//
// Firestore: incident_updates/{autoId}  (create-only, like reports)
//   reportId  - Firestore doc id of the report
//   userId    - who answered
//   vote      - "cleared" | "still"
//   createdAt - server time
//
// Rules (only the LATEST answer of each user counts):
//   1. The person who reported it says "cleared"          -> CLEARED
//   2. 2+ different people say "cleared" and "cleared"
//      answers are more than "still there" answers        -> CLEARED
//   3. No answers: it ends by itself after its active time
//        Accident 6 h · Fire 12 h · Fight 6 h ·
//        Harassment 7 days · Road Damage 30 days
//   4. Test incidents (isTest) end by themselves after 2 hours.
//
// ACTIVE incidents are used for live route alerts and re-routing.
// CLEARED / ended incidents still count 30 % in the area's safety score
// (history), so a place with many past incidents is not shown as perfectly
// safe the next minute.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/incident_model.dart';

class IncidentVotes {
  final Set<String> clearedBy; // users whose latest answer is "cleared"
  final int still;
  final DateTime? lastVoteAt;
  final String? myVote; // current user's latest answer

  const IncidentVotes({
    this.clearedBy = const {},
    this.still = 0,
    this.lastVoteAt,
    this.myVote,
  });

  int get cleared => clearedBy.length;

  bool reporterCleared(String? reporterId) =>
      reporterId != null && clearedBy.contains(reporterId);

  bool clearedFor(String? reporterId) =>
      reporterCleared(reporterId) || (cleared >= 2 && cleared > still);
}

class IncidentStatusService {
  IncidentStatusService._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection("incident_updates");

  static const Map<String, Duration> activeWindow = {
    "Accident": Duration(hours: 6),
    "Fire": Duration(hours: 12),
    "Fight": Duration(hours: 6),
    "Harassment": Duration(days: 7),
    "Road Damage": Duration(days: 30),
  };
  static const Duration testWindow = Duration(hours: 2);

  /// Live answers of all incidents: report doc id -> votes.
  static Stream<Map<String, IncidentVotes>> watchVotes() {
    final me = FirebaseAuth.instance.currentUser?.uid;
    return _col.snapshots().map((snap) => _aggregate(snap.docs, me));
  }

  /// Live answers of ONE incident (incident details screen).
  static Stream<IncidentVotes> watchVotesOf(String reportDocId) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    return _col
        .where("reportId", isEqualTo: reportDocId)
        .snapshots()
        .map((snap) => _aggregate(snap.docs, me)[reportDocId] ??
            const IncidentVotes());
  }

  static Map<String, IncidentVotes> _aggregate(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, String? me) {
    // latest answer per (report, user)
    final latest = <String, Map<String, MapEntry<String, DateTime>>>{};
    for (final d in docs) {
      final m = d.data();
      final rid = (m["reportId"] ?? "").toString();
      final uid = (m["userId"] ?? "").toString();
      final vote = (m["vote"] ?? "").toString();
      if (rid.isEmpty || uid.isEmpty) continue;
      if (vote != "cleared" && vote != "still") continue;
      final ts = m["createdAt"];
      final at = ts is Timestamp ? ts.toDate() : DateTime.now();
      final perUser = latest.putIfAbsent(rid, () => {});
      final old = perUser[uid];
      if (old == null || at.isAfter(old.value)) {
        perUser[uid] = MapEntry(vote, at);
      }
    }

    final out = <String, IncidentVotes>{};
    latest.forEach((rid, users) {
      final clearedBy = <String>{};
      int still = 0;
      DateTime? last;
      for (final e in users.entries) {
        if (e.value.key == "cleared") {
          clearedBy.add(e.key);
        } else {
          still++;
        }
        final at = e.value.value;
        if (last == null || at.isAfter(last)) last = at;
      }
      out[rid] = IncidentVotes(
        clearedBy: clearedBy,
        still: still,
        lastVoteAt: last,
        myVote: me == null ? null : users[me]?.key,
      );
    });
    return out;
  }

  /// "cleared" (true) or "still there" (false) answer of the current user.
  static Future<void> vote(String reportDocId, bool cleared) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError("Please log in first");
    await _col.add({
      "reportId": reportDocId,
      "userId": uid,
      "vote": cleared ? "cleared" : "still",
      "createdAt": FieldValue.serverTimestamp(),
    });
  }

  /// true if the incident was cleared by people's answers (not by time).
  static bool clearedByVotes(IncidentModel i, IncidentVotes? v) =>
      v != null && v.clearedFor(i.userId);

  /// Why an incident is no longer active (null = still active).
  static String? endReason(IncidentModel i, IncidentVotes? v,
      [DateTime? now]) {
    final t = now ?? DateTime.now();
    if (v != null && v.reporterCleared(i.userId)) {
      return "Marked cleared by the reporter";
    }
    if (v != null && v.clearedFor(i.userId)) {
      return "Marked cleared by ${v.cleared} people";
    }
    return timeEndReason(i.category, i.createdAt, i.isTest, t);
  }

  /// "Ended" text when the active time has passed, else null.
  static String? timeEndReason(
      String category, DateTime? createdAt, bool isTest, DateTime now) {
    if (createdAt == null) return null; // just submitted
    final window =
        isTest ? testWindow : (activeWindow[category] ?? const Duration(hours: 12));
    if (now.difference(createdAt) > window) {
      return "Ended (no new reports for ${_fmt(window)})";
    }
    return null;
  }

  static String _fmt(Duration d) =>
      d.inDays >= 1 ? "${d.inDays} day(s)" : "${d.inHours} h";

  static bool isActive(IncidentModel i, IncidentVotes? v, [DateTime? now]) =>
      endReason(i, v, now) == null;

  /// Copies of [list] with `resolved` set from the answers / active time.
  static List<IncidentModel> applyStatus(
      List<IncidentModel> list, Map<String, IncidentVotes> votes) {
    final now = DateTime.now();
    return [
      for (final i in list) i.withResolved(!isActive(i, votes[i.id], now))
    ];
  }
}
