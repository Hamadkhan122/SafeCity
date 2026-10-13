// SafeCity - Route Guard: live incident check while navigating
// =============================================================
// Committee requirement: "If an incident happens ON the safe route while
// the user is driving on it, the app must react at run time."
//
// Every time the incident list or the user's position changes during
// navigation, RouteGuard looks at the PART OF THE ROUTE STILL AHEAD and
// returns the nearest ACTIVE incident that is
//   - within [corridorMeters] (80 m) of the remaining route, and
//   - at least [minAheadMeters] (30 m) ahead (not one already passed).
// MapScreen then shows an alert and computes a new safe route from the
// user's CURRENT position that goes around it.
//
// Pure Dart (no Flutter / Firebase), so it can be unit-tested.

import 'dart:math' as math;

import '../models/incident_model.dart';

class RouteHazard {
  final IncidentModel incident;
  final double metersAhead; // along the route
  final double metersFromRoute; // sideways distance

  const RouteHazard(this.incident, this.metersAhead, this.metersFromRoute);
}

class RouteGuard {
  RouteGuard._();

  static const double corridorMeters = 80;
  static const double minAheadMeters = 30;
  static const double offRouteMeters = 120;

  /// Index of the route point closest to the user.
  static int nearestIndex(List<List<double>> route, List<double> me) {
    int best = 0;
    double bd = double.infinity;
    for (int i = 0; i < route.length; i++) {
      final d = dist(route[i], me);
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  /// Distance from the user to the route (to detect "left the route").
  static double distanceToRoute(List<List<double>> route, List<double> me) {
    double best = double.infinity;
    for (int i = 1; i < route.length; i++) {
      best = math.min(best, _pointToSegment(me, route[i - 1], route[i]));
    }
    if (route.length == 1) best = dist(route.first, me);
    return best;
  }

  /// Nearest active incident ahead on the remaining route, or null.
  /// [ignoreIds] = incidents the user already chose to ignore.
  static RouteHazard? hazardAhead({
    required List<List<double>> route,
    required List<double> me,
    required List<IncidentModel> activeIncidents,
    Set<String> ignoreIds = const {},
  }) {
    if (route.length < 2) return null;
    final start = nearestIndex(route, me);

    // cumulative distance along the remaining route
    final remaining = route.sublist(start);
    final along = <double>[0];
    for (int i = 1; i < remaining.length; i++) {
      along.add(along[i - 1] + dist(remaining[i - 1], remaining[i]));
    }
    final offset = dist(me, remaining.first);

    RouteHazard? best;
    for (final inc in activeIncidents) {
      if (ignoreIds.contains(inc.id)) continue;
      final p = [inc.latitude, inc.longitude];
      double bestSide = double.infinity;
      double bestAlong = 0;
      for (int i = 1; i < remaining.length; i++) {
        final side = _pointToSegment(p, remaining[i - 1], remaining[i]);
        if (side < bestSide) {
          bestSide = side;
          bestAlong = along[i - 1] +
              dist(remaining[i - 1], p)
                  .clamp(0.0, along[i] - along[i - 1])
                  .toDouble();
        }
      }
      if (bestSide > corridorMeters) continue;
      final ahead = bestAlong - offset;
      if (ahead < minAheadMeters) continue;
      if (best == null || ahead < best.metersAhead) {
        best = RouteHazard(inc, ahead, bestSide);
      }
    }
    return best;
  }

  /// true if [route] passes within [corridorMeters] of [inc].
  static bool passesNear(List<List<double>> route, IncidentModel inc) {
    final p = [inc.latitude, inc.longitude];
    for (int i = 1; i < route.length; i++) {
      if (_pointToSegment(p, route[i - 1], route[i]) <= corridorMeters) {
        return true;
      }
    }
    return false;
  }

  /// Point [t] metres along [route] from its start (for the drive simulator).
  static List<double> pointAlong(List<List<double>> route, double t) {
    double acc = 0;
    for (int i = 1; i < route.length; i++) {
      final seg = dist(route[i - 1], route[i]);
      if (acc + seg >= t) {
        final f = seg == 0 ? 0.0 : (t - acc) / seg;
        return [
          route[i - 1][0] + (route[i][0] - route[i - 1][0]) * f,
          route[i - 1][1] + (route[i][1] - route[i - 1][1]) * f,
        ];
      }
      acc += seg;
    }
    return route.last;
  }

  static double length(List<List<double>> route) {
    double acc = 0;
    for (int i = 1; i < route.length; i++) {
      acc += dist(route[i - 1], route[i]);
    }
    return acc;
  }

  // ---------------- geometry ([lat, lng], metres) ----------------
  static double dist(List<double> a, List<double> b) {
    const r = 6371000.0;
    final dLat = (b[0] - a[0]) * math.pi / 180;
    final dLng = (b[1] - a[1]) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a[0] * math.pi / 180) *
            math.cos(b[0] * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
  }

  /// Distance from point p to segment a-b (local flat projection).
  static double _pointToSegment(
      List<double> p, List<double> a, List<double> b) {
    final cosLat = math.cos(a[0] * math.pi / 180);
    double x(List<double> q) => (q[1] - a[1]) * 111320 * cosLat;
    double y(List<double> q) => (q[0] - a[0]) * 110540;
    final bx = x(b), by = y(b), px = x(p), py = y(p);
    final len2 = bx * bx + by * by;
    double t = len2 == 0 ? 0 : (px * bx + py * by) / len2;
    t = t.clamp(0.0, 1.0).toDouble();
    final dx = px - t * bx, dy = py - t * by;
    return math.sqrt(dx * dx + dy * dy);
  }
}
