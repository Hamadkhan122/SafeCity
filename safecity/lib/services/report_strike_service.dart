// SafeCity - False-report strikes and reporting restriction
// ==========================================================
// Backs the warning on the report screen: "Submitting false information may
// result in account restrictions."
//
// What counts as a strike (only clear evidence of a DELIBERATE fake, never
// an honest bad photo or weak GPS):
//   screen    - photo taken of a laptop / monitor / phone screen
//   fake_gps  - mock / fake GPS location detected
//   duplicate - same user, same category, < 200 m, < 30 min
//   spam      - more than 5 reports in one hour
// All strikes come from AIVE's own checks (no manual / community review).
//
// Proof: every strike is stored ON THE REPORT itself
//   reports/{id}.strike       = reason code
//   reports/{id}.aive.flags   = AI evidence (screen score, GPS ...)
//   reports/{id}.imageUrl     = the photo
// Nothing is stored on the user, so there is no separate counter that could
// be edited; strikes are always recounted from the user's own reports.
// Firestore rules make reports read-only after creation (no update/delete),
// so a strike can never be removed.
//
// Restriction (last 30 days):
//   1-2 strikes -> warning (and AIVE uses a stricter threshold from 2)
//   3-4 strikes -> reporting blocked for 7 days after the latest strike
//   5+  strikes -> reporting blocked for 30 days after the latest strike

import 'package:cloud_firestore/cloud_firestore.dart';

class StrikeReason {
  static const screen = "screen";
  static const fakeGps = "fake_gps";
  static const duplicate = "duplicate";
  static const spam = "spam";

  static String label(String code) {
    switch (code) {
      case screen:
        return "Photo was taken of a screen (not a live scene)";
      case fakeGps:
        return "Fake / mock GPS location";
      case duplicate:
        return "Duplicate report";
      case spam:
        return "Too many reports in one hour";
      default:
        return code;
    }
  }
}

class Strike {
  final String reportId;
  final String category;
  final String reason;
  final DateTime at;
  final String imageUrl;
  final List<String> evidence;

  const Strike({
    required this.reportId,
    required this.category,
    required this.reason,
    required this.at,
    required this.imageUrl,
    required this.evidence,
  });
}

class ReporterStanding {
  final List<Strike> strikes; // last 30 days, newest first
  final DateTime? restrictedUntil;

  const ReporterStanding(this.strikes, this.restrictedUntil);

  int get count => strikes.length;
  bool get isRestricted =>
      restrictedUntil != null && DateTime.now().isBefore(restrictedUntil!);
}

class ReportStrikeService {
  static const Duration window = Duration(days: 30);
  static const int warnAt = 1;
  static const int restrictAt = 3;
  static const int longRestrictAt = 5;
  static const Duration shortBlock = Duration(days: 7);
  static const Duration longBlock = Duration(days: 30);

  final FirebaseFirestore firestore;
  ReportStrikeService({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  /// Strike code for an AIVE result, or null if the report was not a
  /// deliberate fake. [flags] are the AIVE flags.
  static String? strikeFromFlags(List<String> flags) {
    bool has(String s) => flags.any((f) => f.contains(s));
    if (has("taken of a screen")) return StrikeReason.screen;
    if (has("Fake (mock) GPS")) return StrikeReason.fakeGps;
    if (has("Duplicate of your earlier report")) return StrikeReason.duplicate;
    if (has("Too many reports")) return StrikeReason.spam;
    return null;
  }

  Future<ReporterStanding> standing(String? userId) async {
    if (userId == null) return const ReporterStanding([], null);
    final since = DateTime.now().subtract(window);
    final snap = await firestore
        .collection("reports")
        .where("userId", isEqualTo: userId)
        .limit(300)
        .get()
        .timeout(const Duration(seconds: 10));

    final strikes = <Strike>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      final reason = d["strike"];
      if (reason is! String || reason.isEmpty) continue;
      final ts = d["createdAt"];
      final at = ts is Timestamp ? ts.toDate() : DateTime.now();
      if (at.isBefore(since)) continue;
      final aive = d["aive"] is Map ? d["aive"] as Map : const {};
      strikes.add(Strike(
        reportId: (d["reportId"] ?? doc.id).toString(),
        category: (d["category"] ?? "").toString(),
        reason: reason,
        at: at,
        imageUrl: (d["imageUrl"] ?? "").toString(),
        evidence: ((aive["flags"] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      ));
    }
    strikes.sort((a, b) => b.at.compareTo(a.at));

    DateTime? until;
    if (strikes.length >= longRestrictAt) {
      until = strikes.first.at.add(longBlock);
    } else if (strikes.length >= restrictAt) {
      until = strikes.first.at.add(shortBlock);
    }
    return ReporterStanding(strikes, until);
  }
}
