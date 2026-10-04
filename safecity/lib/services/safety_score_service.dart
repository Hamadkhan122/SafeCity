// SafeCity - Safety Score Service (M4)
// =====================================================
// Pure Dart (no Firebase / Flutter calls). ONE algorithm is used by:
//   - Map screen      : score of the user's area (1 km)
//   - Safety Score    : score of any searched area (3 km)
//   - Heatmap         : risk level of every zone
//   - Safe Route (M5) : score of every alternative route
// so the features always agree with each other.
//
// ALGORITHM (exact)
// ---------
// 1. Counted reports: every report that is not Rejected (Suspicious).
// 2. SAME INCIDENT rule (also used by AIVE): same category AND <= 200 m
//    apart AND <= 3 hours apart. Reports of the same incident form ONE
//    incident. Its location and time are those of the FIRST report;
//    n = number of reports of that incident.
//       duplicates factor = 1 + 0.25 x min(n - 1, 2)   (1.00 / 1.25 / 1.50)
// 3. Every area starts at 100. Each incident i inside the radius R:
//
//    deduction_i = W(category) x T(age) x D(distance) x duplicates factor
//
//    W  Fire 25 · Accident 20 · Fight 15 · Harassment 12 · Road Damage 6
//    T  age <= 1 day 1.0 · <= 7 days 0.7 · <= 30 days 0.4 · <= 90 days 0.2 ·
//       older 0
//    D  distance <= R/3 1.0 · <= 2R/3 0.6 · <= R 0.3 · outside R 0
//
//    Safety Score = round(100 - sum(deduction_i)), never below 0
//    70-100 Safe · 40-69 Moderate · 0-39 Unsafe
//
// 4. Radius R used by each screen:
//    Live Map card 1 km · Safety Score screen 1 / 2 / 3 / 5 km (default 3) ·
//    Heatmap zone 700 m around the zone centre · Safe Route 300 m around
//    points sampled every 150 m along the route
//    (route score = round(0.7 x average + 0.3 x worst sample)).
//
// 5. Heatmap shows the SAME score with other labels:
//    85-100 Low · 70-84 Medium · 40-69 Medium-High · 0-39 High
//
// TEST CASES (centre of a 3 km radius, all reports today):
//   one fire                       100 - 25            = 75 Safe
//   two different accidents        100 - 20 - 20       = 60 Moderate
//   one accident reported by 2     100 - 20 x 1.25     = 75 Safe
//   one road damage                100 - 6             = 94 Safe
//   fire older than 90 days        100 - 25 x 0        = 100 Safe

import 'dart:math' as math;

import 'package:flutter/material.dart' show Color;

import '../models/incident_model.dart';

enum SafetyLevel { safe, moderate, unsafe }

class SafetyResult {
  final int score; // 0 - 100
  final SafetyLevel level;
  final double totalRisk;
  final int incidentCount; // distinct incidents inside the radius
  final Map<String, int> categoryCounts;

  const SafetyResult({
    required this.score,
    required this.level,
    required this.totalRisk,
    required this.incidentCount,
    required this.categoryCounts,
  });

  String get label {
    switch (level) {
      case SafetyLevel.safe:
        return "Safe";
      case SafetyLevel.moderate:
        return "Moderate";
      case SafetyLevel.unsafe:
        return "Unsafe";
    }
  }

  Color get color {
    switch (level) {
      case SafetyLevel.safe:
        return const Color(0xff2E7D32);
      case SafetyLevel.moderate:
        return const Color(0xffF9A825);
      case SafetyLevel.unsafe:
        return const Color(0xffC62828);
    }
  }
}

class RouteSafetyResult {
  final int score; // weighted: 70% average + 30% worst point
  final int averageScore;
  final int worstScore;
  final SafetyLevel level;
  final int incidentsNearRoute;

  const RouteSafetyResult({
    required this.score,
    required this.averageScore,
    required this.worstScore,
    required this.level,
    required this.incidentsNearRoute,
  });
}

/// Several reports of the same incident merged into one.
class _Incident {
  final String category;
  final double lat;
  final double lng;
  final DateTime? createdAt; // first report
  final double trust; // 1 = counts
  final int reports;

  const _Incident(this.category, this.lat, this.lng, this.createdAt,
      this.trust, this.reports);

  double get corroboration => math.min(1.5, 1 + 0.25 * (reports - 1));
}

class SafetyScoreService {
  static const double defaultRadiusMeters = 1000; // Live Map (current area)
  static const double searchRadiusMeters = 3000; // Safety Score search
  static const double routeCorridorMeters = 300;
  static const double routeSampleSpacingMeters = 150;

  // Duplicate merge: same category within this distance and time.
  // SAME INCIDENT rule (same as AiveService.sameIncidentMeters / Window).
  static const double duplicateMeters = 200;
  static const Duration duplicateWindow = Duration(hours: 3);

  /// Incident categories the app supports. "Theft" was removed from the
  /// project, so any old Theft reports in Firestore are ignored everywhere.
  static const List<String> categories = [
    "Accident",
    "Fire",
    "Harassment",
    "Road Damage",
    "Fight",
  ];

  static bool isSupportedCategory(String category) =>
      categories.contains(category);

  /// Points an incident takes away from 100 (category points).
  static const Map<String, double> categoryPoints = {
    "Fire": 25,
    "Accident": 20,
    "Fight": 15,
    "Harassment": 12,
    "Road Damage": 6,
  };

  /// Kept for older callers: same order as [categoryPoints].
  static Map<String, double> get severity => categoryPoints;

  /// Time factor: today 100 %, 2-7 days 70 %, 8-30 days 40 %,
  /// 31-90 days 20 %, older 0 %.
  static double timeFactor(DateTime? createdAt, DateTime now) {
    if (createdAt == null) return 1.0; // just submitted
    final days = now.difference(createdAt).inHours / 24;
    if (days <= 1) return 1.0;
    if (days <= 7) return 0.7;
    if (days <= 30) return 0.4;
    if (days <= 90) return 0.2;
    return 0;
  }

  /// Distance factor: inner third of the radius 100 %, middle 60 %,
  /// outer third 30 %.
  static double distanceFactor(double d, double radius) {
    if (d <= radius / 3) return 1.0;
    if (d <= radius * 2 / 3) return 0.6;
    return 0.3;
  }

  // ---------------------------------------------------------------
  // Point score
  // ---------------------------------------------------------------
  static SafetyResult scoreAt({
    required double lat,
    required double lng,
    required List<IncidentModel> incidents,
    double radiusMeters = defaultRadiusMeters,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    double totalRisk = 0;
    int count = 0;
    final counts = <String, int>{};

    // Cheap bounding-box prefilter before the haversine call.
    final latDelta = radiusMeters / 111000;
    final lngDelta = radiusMeters /
        (111000 * math.cos(lat * math.pi / 180).abs().clamp(0.01, 1));

    for (final inc in _merged(incidents)) {
      if ((inc.lat - lat).abs() > latDelta) continue;
      if ((inc.lng - lng).abs() > lngDelta) continue;

      final d = distanceMeters(lat, lng, inc.lat, inc.lng);
      if (d > radiusMeters) continue;

      final risk = incidentRisk(inc.category, inc.createdAt, inc.trust, t) *
          inc.corroboration *
          distanceFactor(d, radiusMeters);
      if (risk <= 0) continue;

      totalRisk += risk;
      count++;
      counts[inc.category] = (counts[inc.category] ?? 0) + 1;
    }

    final score = scoreFromRisk(totalRisk);
    return SafetyResult(
      score: score,
      level: levelFor(score),
      totalRisk: totalRisk,
      incidentCount: count,
      categoryCounts: counts,
    );
  }

  /// Points one report / incident takes away (category x time x trust),
  /// before the distance factor.
  static double incidentRisk(
      String category, DateTime? createdAt, double trust, DateTime now) {
    if (!isSupportedCategory(category) || trust <= 0) return 0;
    return (categoryPoints[category] ?? 15) * timeFactor(createdAt, now) * trust;
  }

  /// score = 100 - points lost (never below 0).
  static int scoreFromRisk(double totalPointsLost) =>
      (100 - totalPointsLost).round().clamp(0, 100).toInt();

  // ---------------------------------------------------------------
  // Route score — samples the polyline every ~150 m and scores each
  // sample with a narrow corridor radius (300 m).
  // `points` = list of [lat, lng] pairs (decoded polyline).
  // ---------------------------------------------------------------
  static RouteSafetyResult scoreRoute({
    required List<List<double>> points,
    required List<IncidentModel> incidents,
    DateTime? now,
  }) {
    final samples = _samplePolyline(points, routeSampleSpacingMeters);
    if (samples.isEmpty) {
      return const RouteSafetyResult(
        score: 100,
        averageScore: 100,
        worstScore: 100,
        level: SafetyLevel.safe,
        incidentsNearRoute: 0,
      );
    }

    int sum = 0;
    int worst = 100;
    for (final p in samples) {
      final r = scoreAt(
        lat: p[0],
        lng: p[1],
        incidents: incidents,
        radiusMeters: routeCorridorMeters,
        now: now,
      );
      sum += r.score;
      if (r.score < worst) worst = r.score;
    }

    final avg = (sum / samples.length).round();
    final weighted = (0.7 * avg + 0.3 * worst).round();

    return RouteSafetyResult(
      score: weighted,
      averageScore: avg,
      worstScore: worst,
      level: levelFor(weighted),
      incidentsNearRoute: _countNearRoute(samples, incidents, now),
    );
  }

  /// Serious, recent incidents in the area between origin and destination
  /// (box + ~1 km margin), most dangerous first. The directions service
  /// builds alternative routes that go around them.
  static List<List<double>> hotspotsBetween({
    required double oLat,
    required double oLng,
    required double dLat,
    required double dLng,
    required List<IncidentModel> incidents,
    int max = 3,
    double minRisk = 15, // points: e.g. a fight / fire / accident <= 7 days
  }) {
    final now = DateTime.now();
    const margin = 0.01; // ~1 km
    final minLat = math.min(oLat, dLat) - margin;
    final maxLat = math.max(oLat, dLat) + margin;
    final minLng = math.min(oLng, dLng) - margin;
    final maxLng = math.max(oLng, dLng) + margin;
    final found = <MapEntry<double, List<double>>>[];
    for (final inc in _merged(incidents)) {
      if (inc.lat < minLat || inc.lat > maxLat) continue;
      if (inc.lng < minLng || inc.lng > maxLng) continue;
      final risk = incidentRisk(inc.category, inc.createdAt, inc.trust, now) *
          inc.corroboration;
      if (risk >= minRisk) found.add(MapEntry(risk, [inc.lat, inc.lng]));
    }
    found.sort((a, b) => b.key.compareTo(a.key));
    return found.take(max).map((e) => e.value).toList();
  }

  static SafetyLevel levelFor(int score) {
    if (score >= 70) return SafetyLevel.safe;
    if (score >= 40) return SafetyLevel.moderate;
    return SafetyLevel.unsafe;
  }

  // ---------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------

  /// 1 = the report counts, 0 = Rejected (does not count).
  static double trustFor(String status) =>
      (status == "Suspicious" || status == "Rejected") ? 0 : 1.0;

  /// Map / heatmap visibility. Only reports AIVE flagged as Suspicious (or
  /// Rejected) are hidden — old "Pending" reports stay visible as before.
  static bool isPublicStatus(String status) =>
      status != "Suspicious" && status != "Rejected";

  /// Status AND category check for raw Firestore maps (map, heatmap, feed).
  static bool isPublicReport(Map<String, dynamic> data) =>
      isPublicStatus((data["status"] ?? "").toString()) &&
      isSupportedCategory((data["category"] ?? "").toString());

  /// Time factor of a report (see [timeFactor]).
  static double recencyWeight(DateTime? createdAt,
      [DateTime? now, String? category]) =>
      timeFactor(createdAt, now ?? DateTime.now());

  // ---- Duplicate merge (cached: the same list is scored many times) ----
  static List<IncidentModel>? _cacheKey;
  static int _cacheLen = -1;
  static List<_Incident> _cacheValue = const [];

  static List<_Incident> _merged(List<IncidentModel> incidents) {
    if (identical(incidents, _cacheKey) && incidents.length == _cacheLen) {
      return _cacheValue;
    }
    final usable = incidents
        .where((i) =>
            isSupportedCategory(i.category) && trustFor(i.status) > 0)
        .toList()
      // oldest first: the FIRST report of an incident is its base
      ..sort((a, b) => (a.createdAt ?? DateTime(2100))
          .compareTo(b.createdAt ?? DateTime(2100)));

    final groups = <List<IncidentModel>>[];
    for (final inc in usable) {
      List<IncidentModel>? home;
      for (final g in groups) {
        final f = g.first;
        if (f.category != inc.category) continue;
        final dt = (f.createdAt ?? DateTime.now())
            .difference(inc.createdAt ?? DateTime.now())
            .abs();
        if (dt > duplicateWindow) continue;
        if (distanceMeters(
                f.latitude, f.longitude, inc.latitude, inc.longitude) <=
            duplicateMeters) {
          home = g;
          break;
        }
      }
      if (home != null) {
        home.add(inc);
      } else {
        groups.add([inc]);
      }
    }

    final out = <_Incident>[];
    for (final g in groups) {
      final f = g.first; // first report = location and time of the incident
      out.add(_Incident(
          f.category, f.latitude, f.longitude, f.createdAt, 1.0, g.length));
    }

    _cacheKey = incidents;
    _cacheLen = incidents.length;
    _cacheValue = out;
    return out;
  }

  static int _countNearRoute(List<List<double>> samples,
      List<IncidentModel> incidents, DateTime? now) {
    int n = 0;
    final t = now ?? DateTime.now();
    for (final inc in _merged(incidents)) {
      // Very old reports (weight < 5 %) are not "near the route" any more.
      if (recencyWeight(inc.createdAt, t, inc.category) < 0.05) continue;
      for (final p in samples) {
        if (distanceMeters(p[0], p[1], inc.lat, inc.lng) <=
            routeCorridorMeters) {
          n++;
          break;
        }
      }
    }
    return n;
  }

  static List<List<double>> _samplePolyline(
      List<List<double>> pts, double spacing) {
    if (pts.isEmpty) return [];
    final out = <List<double>>[pts.first];
    double carried = 0;

    for (int i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final seg = distanceMeters(a[0], a[1], b[0], b[1]);
      if (seg == 0) continue;

      double pos = spacing - carried;
      while (pos <= seg) {
        final f = pos / seg;
        out.add([a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f]);
        pos += spacing;
      }
      carried = (carried + seg) % spacing;
    }

    if (out.last != pts.last) out.add(pts.last);
    return out;
  }

  static double distanceMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }
}
