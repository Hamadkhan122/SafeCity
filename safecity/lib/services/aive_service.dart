// SafeCity - AI Incident Verification Engine (AIVE)
// =====================================================
// SRS 1.2 / SDD evaluation history: every report is evaluated automatically
// (no admin) and gets ONE of two results:
//   Verified   -> public (map, heatmap, notifications)
//   Suspicious -> shown to the user as "Rejected", hidden from the public
//
// Every report goes through these checks. EACH check is saved with the
// report (pass / fail + reason), so a rejected report always shows exactly
// what failed: photo, description, GPS, time, duplicate or spam.
//
//   Check        Fails when                                         Hard?
//   Photo        no incident in the photo / other incident / AI     yes
//                could not run / no fighting (Fight) / no people
//                (Harassment)
//   Live photo   photo taken of a laptop / phone / TV screen        yes
//   Description  does not describe the incident, describes another  yes
//                incident, or says it is not there (Eng/Roman Urdu/Urdu)
//   GPS          fake (mock) GPS                                    yes
//                low accuracy -> lower score only                   no
//   Time         photo / location too old -> lower score only       no
//   Duplicate    same user, same incident (see SAME INCIDENT rule)  yes
//   Spam         user already has 5 reports in the last 60 minutes  yes
//
// POINTS (total 100, whole numbers; total = sum of the check points)
//   Photo           40  round(AI confidence x 40)   e.g. 91 % -> 36
//                       AI confidence = model probability for the selected
//                       category (Harassment: max(people visible, violence))
//   Location (GPS)  25  accuracy <= 20 m 25 · <= 50 m 20 · <= 100 m 13 ·
//                       > 100 m 5 · fake (mock) GPS 0 + REJECT
//   Description     15  matches the category 15 · close category 11
//                       (Fight<->Harassment, Accident<->Road Damage) ·
//                       other category / no incident / "not there" 0 + REJECT
//   Time            10  photo age (capture -> submit): <= 5 min 5 ·
//                       <= 15 min 3 · older 1;  location fix age:
//                       <= 2 min 5 · <= 10 min 3 · older 1
//   Nearby reports  10  matching reports by OTHER users: none 5 · one 8 ·
//                       two or more 10
//
// SAME INCIDENT rule (used everywhere): same category AND <= 200 m apart
// AND <= 3 hours apart. A matching report by another user = nearby report.
// The same user reporting the same incident again = Duplicate (REJECT).
// Spam: the user already has 5 reports in the last 60 minutes (REJECT).
//
// AI confidence (photo model %) and the verification score (points /100)
// are different numbers; the UI always labels them separately.
//
// DECISION
//   mandatory checks: photo present and shows the incident, live photo
//   (not a screen), description, GPS not fake, not duplicate, not spam
//   if any mandatory check fails          -> REJECTED (Suspicious)
//   else if strikes (30 days) >= 2        -> VERIFIED if total >= 80
//   else                                  -> VERIFIED if total >= 60
//   else                                  -> REJECTED
//
// The image classifier is pluggable (SRS SUP-3): pass any ImageClassifier.

import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import 'description_matcher.dart';
import 'report_strike_service.dart';
import 'safety_score_service.dart';

class AiveStatus {
  static const verified = "Verified";
  // Kept only so that old reports saved with this status still display.
  static const partiallyVerified = "Partially Verified";
  static const suspicious = "Suspicious";
}

/// What the image model(s) say about one photo.
class ImageAnalysis {
  /// Model probability (0..1) for the selected category.
  /// null = no model for this category.
  final double? categoryScore;
  final double? rawProbability;

  /// Probability that the photo was taken of a screen (recapture).
  final double screenProbability;

  /// Probability that people are visible in the photo.
  final double personProbability;

  /// Most likely incident-model label and its probability.
  final String topLabel;
  final double topProbability;

  /// True for people-based categories (Fight, Harassment).
  final bool usesFloor;

  /// Every model output (for the AI Test Lab screen).
  final Map<String, double> probabilities;

  const ImageAnalysis({
    required this.categoryScore,
    this.rawProbability,
    this.screenProbability = 0,
    this.personProbability = 0,
    this.topLabel = "",
    this.topProbability = 0,
    this.usesFloor = false,
    this.probabilities = const {},
  });
}

/// Hook for the ML model (TFLite on-device or a REST endpoint).
/// Returns null if the photo could not be analysed.
abstract class ImageClassifier {
  Future<ImageAnalysis?> analyze(String category, File image);
}

class NoImageClassifier implements ImageClassifier {
  const NoImageClassifier();
  @override
  Future<ImageAnalysis?> analyze(String category, File image) async => null;
}

/// Incident-model label -> report category (for "photo looks like X").
const Map<String, String> _labelToCategory = {
  "accident": "Accident",
  "fire": "Fire",
  "road_damage": "Road Damage",
  "fighting": "Fight",
};

/// One verification check with its result, shown to the user.
class AiveCheck {
  final String name; // Photo, Live photo, Description, GPS, Time, ...
  final bool passed;
  final String detail; // why it passed / failed
  final bool hard; // a failed hard check rejects the report
  final int? points; // points earned (null = rule only, no points)
  final int? maxPoints;

  const AiveCheck(this.name, this.passed, this.detail,
      {this.hard = true, this.points, this.maxPoints});

  /// "Photo (36/40)" or just "Duplicate".
  String get title =>
      maxPoints == null ? name : "$name ($points/$maxPoints)";

  Map<String, dynamic> toMap() => {
        "name": name,
        "passed": passed,
        "detail": detail,
        "hard": hard,
        if (maxPoints != null) "points": points,
        if (maxPoints != null) "maxPoints": maxPoints,
      };
}

/// Result of the photo check alone. Used both by the live photo check on
/// the report screen and by AIVE at submit, so both always agree:
/// green ring = photo passed, red ring = report will be rejected.
class PhotoVerdict {
  final bool passed;
  final double score; // image score used in the AIVE formula (0..1)
  final List<String> flags;
  final double screenScore;
  final String label; // what the incident model sees
  final bool isScreen; // failed because it is a photo of a screen

  const PhotoVerdict({
    required this.passed,
    required this.score,
    required this.flags,
    this.screenScore = 0,
    this.label = "",
    this.isScreen = false,
  });

  /// Short message for the live photo check.
  String get message =>
      flags.isNotEmpty ? flags.first : "Photo matches the selected category";
}

class AiveResult {
  final String status;
  final double confidence;
  final double imageScore;
  final double descriptionScore;
  final double gpsScore;
  final double timeScore;
  final double nearbyScore;
  final double screenScore; // probability the photo is of a screen
  final String imageLabel; // what the incident model sees in the photo
  final List<String> flags; // human-readable reasons (failed checks first)
  final List<AiveCheck> checks; // every check with pass / fail

  const AiveResult({
    required this.status,
    required this.confidence,
    required this.imageScore,
    this.descriptionScore = 0.5,
    required this.gpsScore,
    required this.timeScore,
    required this.nearbyScore,
    this.screenScore = 0,
    this.imageLabel = "",
    required this.flags,
    this.checks = const [],
  });

  bool get isPublic => status != AiveStatus.suspicious;
  bool get isVerified => status == AiveStatus.verified;

  /// Names of the checks that failed, e.g. "Photo, Description".
  List<AiveCheck> get failedChecks => checks.where((c) => !c.passed).toList();

  Map<String, dynamic> toMap() => {
        "version": 5,
        "screenScore": _r(screenScore),
        "imageLabel": imageLabel,
        "imageScore": _r(imageScore),
        "descriptionScore": _r(descriptionScore),
        "gpsScore": _r(gpsScore),
        "timeScore": _r(timeScore),
        "nearbyScore": _r(nearbyScore),
        "flags": flags,
        "checks": checks.map((c) => c.toMap()).toList(),
      };

  static double _r(double v) => (v * 100).round() / 100;
}

class AiveService {
  // Maximum points (see header): photo > location > description.
  static const int maxPhotoPoints = 40;
  static const int maxGpsPoints = 25;
  static const int maxDescriptionPoints = 15;
  static const int maxTimePoints = 10;
  static const int maxNearbyPoints = 10;

  static const double verifiedThreshold = 0.60; // 60 points

  // SAME INCIDENT rule (nearby reports, duplicates, safety-score merge).
  static const double sameIncidentMeters = 200;
  static const Duration sameIncidentWindow = Duration(hours: 3);

  // Reporter reputation: after this many false-report strikes (30 days) the
  // user needs [flaggedReporterThreshold] instead of [verifiedThreshold].
  static const int falseReportsToFlag = 2;
  static const double flaggedReporterThreshold = 0.80;

  // Photo check thresholds.
  static const double categoryPassMin = 0.50; // Accident / Fire / Road Damage
  static const double fightPassMin = 0.50; // fight-pose check (two people)
  // The incident model alone must be very sure: on our tests a person posing
  // with fists next to a calm friend reached 0.55-0.70 "fighting".
  static const double fightModelMin = 0.80;
  static const double personPassMin = 0.50; // Harassment: people visible
  // Photo of a screen: rejected from 0.40 (tested on our own phone videos:
  // 26 of 28 photos of another phone caught, 0 of 80 live camera frames
  // flagged, about 1.5 % of real incident photos).
  // From 0.60 it is clear enough to count as a strike.
  static const double screenRejectMin = 0.40;
  static const double screenStrikeMin = 0.60;
  static const double otherIncidentMin = 0.80; // clearly another incident

  /// Photo check: turns raw model output into pass / fail + image score.
  static PhotoVerdict photoVerdict(String category, ImageAnalysis? a) {
    if (a == null || a.categoryScore == null) {
      return const PhotoVerdict(
        passed: false,
        score: 0,
        flags: ["AI could not analyse the photo - please retake it"],
      );
    }
    final raw = (a.rawProbability ?? a.categoryScore!).clamp(0.0, 1.0);
    final screen = a.screenProbability;

    // 1. Photo of a screen (Google image on a laptop, phone, TV ...).
    if (screen >= screenRejectMin) {
      return PhotoVerdict(
        passed: false,
        score: 0,
        flags: [
          screen >= screenStrikeMin
              ? "Photo appears to be taken of a screen, not a live scene"
              : "Photo may show a phone / laptop screen - take a live photo of the scene"
        ],
        screenScore: screen,
        label: "screen",
        isScreen: true,
      );
    }

    // 2. Photo clearly shows a DIFFERENT incident type.
    final looksLike = _labelToCategory[a.topLabel];
    final otherIncident = looksLike != null &&
        looksLike != category &&
        a.topProbability >= otherIncidentMin &&
        !(category == "Harassment" && looksLike == "Fight");
    if (otherIncident) {
      return PhotoVerdict(
        passed: false,
        score: 0.1,
        flags: ["Photo looks like $looksLike, not $category"],
        screenScore: screen,
        label: a.topLabel,
      );
    }

    // 3. Photo must show the incident.
    if (category == "Fight") {
      // Fighting must be visible (people + violent action). People alone,
      // hands, or someone standing calmly are not a fight.
      final model = a.probabilities["fighting"] ?? raw;
      final pose = a.probabilities["fight pose"] ?? 0.0;
      final fight = model >= fightModelMin || pose >= fightPassMin;
      final hasPeople = a.personProbability >= personPassMin;
      return PhotoVerdict(
        passed: fight,
        // A rejected fight photo does not show a high confidence.
        score: fight ? raw : math.min(raw, 0.45).toDouble(),
        flags: fight
            ? const []
            : [
                hasPeople
                    ? "No fighting visible in the photo"
                    : "No people visible in the photo"
              ],
        screenScore: screen,
        label: a.topLabel,
      );
    }
    if (category == "Harassment") {
      // Harassment (staring, following, comments) is rarely visible in one
      // photo, so the photo must show people and the description must
      // describe the harassment (checked separately).
      // AI confidence = max(people visible, violence model).
      final conf = math.max(a.personProbability, raw).toDouble();
      final hasPeople = a.personProbability >= personPassMin || raw >= 0.5;
      return PhotoVerdict(
        passed: hasPeople,
        score: conf,
        flags: hasPeople ? const [] : const ["No people visible in the photo"],
        screenScore: screen,
        label: a.topLabel,
      );
    }

    final shows = raw >= categoryPassMin;
    return PhotoVerdict(
      passed: shows,
      score: raw,
      flags:
          shows ? const [] : ["No ${category.toLowerCase()} visible in the photo"],
      screenScore: screen,
      label: a.topLabel,
    );
  }

  final FirebaseFirestore firestore;
  final ImageClassifier classifier;

  AiveService({
    FirebaseFirestore? firestore,
    this.classifier = const NoImageClassifier(),
  }) : firestore = firestore ?? FirebaseFirestore.instance;

  Future<AiveResult> verify({
    required String category,
    required Position position,
    required String? userId,
    String description = "",
    File? image,
    DateTime? imageCapturedAt,
    ImageAnalysis? imageAnalysis, // pass the live photo check to skip re-running
  }) async {
    final now = DateTime.now();
    final checks = <AiveCheck>[];
    final notes = <String>[]; // extra info (not a failed check)

    // ---------------- 1. Photo + live photo ----------------
    double imageScore = 0; // AI confidence for the photo (0..1)
    int photoPoints = 0;
    double screenScore = 0;
    String imageLabel = "";
    if (image == null) {
      checks.add(const AiveCheck("Photo", false, "No photo attached"));
    } else {
      ImageAnalysis? a = imageAnalysis;
      if (a == null) {
        try {
          a = await classifier.analyze(category, image);
        } catch (_) {
          a = null;
        }
      }
      final v = photoVerdict(category, a);
      imageScore = v.score;
      screenScore = v.screenScore;
      imageLabel = v.label;
      checks.add(AiveCheck(
        "Live photo",
        !v.isScreen,
        v.isScreen
            ? v.message
            : "Live camera photo (not a photo of a screen)",
      ));
      photoPoints = v.isScreen ? 0 : (imageScore * 40).round();
      if (!v.isScreen) {
        checks.add(AiveCheck(
          "Photo",
          v.passed,
          points: photoPoints,
          maxPoints: 40,
          "AI confidence ${(imageScore * 100).round()}% · "
          "${v.passed ? "photo shows ${category == "Harassment" ? "people (harassment)" : category.toLowerCase()}" : v.message}",
        ));
      }
    }

    // ---------------- 2. Description ----------------
    final desc = DescriptionMatcher.check(category, description);
    final descPoints =
        desc.kind == "match" ? 15 : (desc.kind == "related" ? 11 : 0);
    final descriptionScore = descPoints / 15;
    checks.add(AiveCheck(
      "Description",
      desc.passed,
      points: descPoints,
      maxPoints: 15,
      desc.passed
          ? (desc.kind == "match"
              ? "Description matches $category"
              : "Description is close to $category")
          : (desc.flag ?? "Description does not match $category"),
    ));

    // ---------------- 3. GPS ----------------
    double gpsScore;
    int gpsPoints = 0;
    if (position.isMocked) {
      gpsScore = 0;
      checks.add(const AiveCheck("Location (GPS)", false, "Fake (mock) GPS location detected",
          points: 0, maxPoints: 25));
    } else {
      final acc = position.accuracy;
      gpsPoints = acc <= 20 ? 25 : acc <= 50 ? 20 : acc <= 100 ? 13 : 5;
      gpsScore = gpsPoints / 25;
      checks.add(AiveCheck(
        "Location (GPS)",
        true,
        acc <= 100
            ? "Real GPS location (±${acc.toStringAsFixed(0)} m)"
            : "Real GPS but low accuracy (±${acc.toStringAsFixed(0)} m) - lower score",
        hard: false,
        points: gpsPoints,
        maxPoints: 25,
      ));
    }

    // ---------------- 4. Time ----------------
    final fixAgeMin = now.difference(position.timestamp).inSeconds / 60;
    final fixPoints = fixAgeMin <= 2 ? 5 : (fixAgeMin <= 10 ? 3 : 1);
    int photoAgePoints = 0;
    double photoAgeMin = 0;
    if (image != null && imageCapturedAt != null) {
      photoAgeMin = now.difference(imageCapturedAt).inSeconds / 60;
      photoAgePoints = photoAgeMin <= 5 ? 5 : (photoAgeMin <= 15 ? 3 : 1);
    }
    final timePoints = fixPoints + photoAgePoints;
    final timeScore = timePoints / 10;
    checks.add(AiveCheck(
      "Time",
      true,
      "Photo taken ${photoAgeMin.round()} min before submitting ($photoAgePoints/5) · "
      "location ${fixAgeMin.round()} min old ($fixPoints/5)",
      hard: false,
      points: timePoints,
      maxPoints: 10,
    ));

    // ---------------- 5. Duplicate / spam / nearby ----------------
    double nearbyScore = 0.5; // first report in the area (5 / 10 points)
    String? duplicateOf;
    int userLastHour = 0;
    int corroborating = 0;
    try {
      final since = Timestamp.fromDate(now.subtract(const Duration(hours: 3)));
      // Single-field range query -> no composite index needed.
      final snap = await firestore
          .collection("reports")
          .where("createdAt", isGreaterThanOrEqualTo: since)
          .get()
          .timeout(const Duration(seconds: 10));

      for (final doc in snap.docs) {
        final d = doc.data();
        if (d["latitude"] == null || d["longitude"] == null) continue;

        final dist = SafetyScoreService.distanceMeters(
          position.latitude,
          position.longitude,
          (d["latitude"] as num).toDouble(),
          (d["longitude"] as num).toDouble(),
        );
        final ts = d["createdAt"];
        final created = ts is Timestamp ? ts.toDate() : now;
        final ageMin = now.difference(created).inMinutes;
        final sameUser = userId != null && d["userId"] == userId;
        final sameCategory = d["category"] == category;

        if (sameUser) {
          if (ageMin <= 60) userLastHour++;
          if (sameCategory &&
              dist <= sameIncidentMeters &&
              ageMin <= sameIncidentWindow.inMinutes) {
            duplicateOf ??= (d["reportId"] ?? "").toString();
          }
        } else if (sameCategory &&
            dist <= sameIncidentMeters &&
            ageMin <= sameIncidentWindow.inMinutes &&
            d["status"] != AiveStatus.suspicious) {
          corroborating++;
        }
      }
      if (corroborating >= 2) {
        nearbyScore = 1.0;
      } else if (corroborating == 1) {
        nearbyScore = 0.8;
      }
    } catch (_) {
      // Offline / query failure -> keep neutral score (REL-4).
    }
    checks.add(AiveCheck(
      "Nearby reports",
      true,
      corroborating > 0
          ? "Matched $corroborating nearby report(s) of the same incident"
          : "First report of this incident in the area",
      hard: false,
      points: corroborating >= 2 ? 10 : (corroborating == 1 ? 8 : 5),
      maxPoints: 10,
    ));
    checks.add(AiveCheck(
      "Duplicate",
      duplicateOf == null,
      duplicateOf == null
          ? "Not a duplicate"
          : "Duplicate of your earlier report $duplicateOf "
              "(same category, within 200 m and 3 hours)",
    ));
    checks.add(AiveCheck(
      "Spam",
      userLastHour < 5,
      userLastHour < 5
          ? "Normal reporting rate"
          : "Too many reports from this account in the last hour ($userLastHour)",
    ));

    // ---------------- Combine ----------------
    // Verification score = sum of the check points (out of 100).
    final nearbyPoints = corroborating >= 2 ? 10 : (corroborating == 1 ? 8 : 5);
    final totalPoints =
        photoPoints + gpsPoints + descPoints + timePoints + nearbyPoints;
    final confidence = (totalPoints / 100).clamp(0.0, 1.0).toDouble();
    final hardFail = checks.any((c) => c.hard && !c.passed);

    // ---------------- Reporter reputation ----------------
    double threshold = verifiedThreshold;
    if (!hardFail && confidence >= verifiedThreshold) {
      int strikes = 0;
      try {
        strikes =
            (await ReportStrikeService(firestore: firestore).standing(userId))
                .count;
      } catch (_) {
        strikes = 0; // offline -> no penalty
      }
      if (strikes >= falseReportsToFlag) {
        threshold = flaggedReporterThreshold;
        notes.add("You have $strikes false-report warnings - "
            "${(threshold * 100).round()} points are required");
      }
    }

    final verified = !hardFail && confidence >= threshold;
    if (!hardFail && !verified) {
      checks.add(AiveCheck(
        "Overall score",
        false,
        "Verification score $totalPoints/100 is below the required "
            "${(threshold * 100).round()}",
      ));
    }

    // Show checks in points order: photo > location > description > ...
    const order = [
      "Live photo", "Photo", "Location (GPS)", "Description", "Time",
      "Nearby reports", "Duplicate", "Spam", "Overall score",
    ];
    checks.sort((a, b) => order.indexOf(a.name).compareTo(order.indexOf(b.name)));

    // Flags: failed checks first (these are the reasons), then notes.
    final flags = <String>[
      for (final c in checks)
        if (!c.passed) c.detail,
      ...notes,
    ];

    return AiveResult(
      status: verified ? AiveStatus.verified : AiveStatus.suspicious,
      confidence: confidence,
      imageScore: imageScore,
      descriptionScore: descriptionScore,
      gpsScore: gpsScore,
      timeScore: timeScore,
      nearbyScore: nearbyScore,
      screenScore: screenScore,
      imageLabel: imageLabel,
      flags: flags,
      checks: checks,
    );
  }
}
