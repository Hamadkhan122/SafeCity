import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Driving directions.
///
/// Order:
///   1. Google Directions API (classic)
///   2. Google Routes API
///   3. OSRM (OpenStreetMap routing) — FREE, no API key, no credit card
/// The answer is always converted to the classic Google shape
/// (routes -> legs[0].distance/duration.text + overview_polyline.points),
/// so MapScreen and the Safe Route scoring don't change.
///
/// ALTERNATIVE ROUTES (Safe Route Suggestion, M5)
/// The free OSRM server returns only ONE route in Abbottabad, so SafeCity
/// builds the alternatives itself (tested on real Abbottabad trips: 3-5
/// different, drivable routes per trip):
///   1. Hotspot avoidance: for every serious incident close to the fastest
///      route ([avoid] points from MapScreen), a waypoint 500 m to its left
///      and right forces a route around it.
///   2. Side routes: waypoints left / right of the fastest route at 1/3,
///      1/2 and 2/3 of the way.
///   3. Clean-up: a waypoint on a side street makes OSRM drive in and come
///      back ("out-and-back"); such routes are re-routed through the point
///      where the detour starts, or dropped. Routes much longer than the
///      fastest (> 60 % or > 10 min) and near-duplicates (> 80 % shared
///      road) are removed. At most [maxRoutes] routes are returned.
/// MapScreen then scores every route with SafetyScoreService and picks the
/// safest one with a reasonable detour.
class DirectionsService {
  static const String apiKey = "AIzaSyAU3UxNT9xlSea9G3iDbIYBDJDqGojSU5s";
  static bool _legacyBlocked = false;
  static bool _routesBlocked = false;

  Future<Map<String, dynamic>?> getDirections({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    bool alternatives = false, // M5: ask for multiple routes
    List<List<double>> avoid = const [], // [lat, lng] incident hotspots
  }) async {
    if (!_legacyBlocked) {
      try {
        final url = "https://maps.googleapis.com/maps/api/directions/json"
            "?origin=$originLat,$originLng"
            "&destination=$destLat,$destLng"
            "&mode=driving"
            "${alternatives ? "&alternatives=true" : ""}"
            "&key=$apiKey";
        final r = await http.get(Uri.parse(url));
        if (r.statusCode == 200) {
          final json = jsonDecode(r.body);
          if (json["status"] == "OK" &&
              json["routes"] != null &&
              json["routes"].isNotEmpty) {
            // Google gave only one route -> build alternatives with OSRM.
            if (alternatives && (json["routes"] as List).length < 2) {
              final o = await _osrm(
                  originLat, originLng, destLat, destLng, true, avoid);
              if (o != null && (o["routes"] as List).length > 1) return o;
            }
            return json;
          }
          debugPrint("getDirections Google status: ${json["status"]} "
              "${json["error_message"] ?? ""}");
          if (json["status"] == "REQUEST_DENIED" ||
              json["status"] == "OVER_QUERY_LIMIT") {
            _legacyBlocked = true;
          }
        }
      } catch (e) {
        debugPrint("getDirections error: $e");
      }
    }

    if (!_routesBlocked) {
      final r = await _routesApi(originLat, originLng, destLat, destLng, alternatives);
      if (r != null && (!alternatives || (r["routes"] as List).length > 1)) {
        return r;
      }
      if (r != null) {
        final o = await _osrm(
            originLat, originLng, destLat, destLng, true, avoid);
        return (o != null && (o["routes"] as List).length > 1) ? o : r;
      }
    }

    return _osrm(originLat, originLng, destLat, destLng, alternatives, avoid);
  }

  static String _km(int m) =>
      m < 1000 ? "$m m" : "${(m / 1000).toStringAsFixed(1)} km";

  static String _mins(int s) {
    final m = (s / 60).round();
    if (m < 60) return "$m min";
    return "${m ~/ 60} hr ${m % 60} min";
  }

  static Map<String, dynamic> _route(String polyline, int meters, int secs) => {
        "overview_polyline": {"points": polyline},
        "legs": [
          {
            "distance": {"text": _km(meters), "value": meters},
            "duration": {"text": _mins(secs), "value": secs},
          }
        ],
      };

  Future<Map<String, dynamic>?> _routesApi(double oLat, double oLng,
      double dLat, double dLng, bool alternatives) async {
    try {
      final r = await http.post(
        Uri.parse("https://routes.googleapis.com/directions/v2:computeRoutes"),
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": apiKey,
          "X-Goog-FieldMask":
              "routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline",
        },
        body: jsonEncode({
          "origin": {
            "location": {
              "latLng": {"latitude": oLat, "longitude": oLng}
            }
          },
          "destination": {
            "location": {
              "latLng": {"latitude": dLat, "longitude": dLng}
            }
          },
          "travelMode": "DRIVE",
          "computeAlternativeRoutes": alternatives,
        }),
      );
      if (r.statusCode != 200) {
        debugPrint("Routes API ${r.statusCode}: ${r.body}");
        if (r.statusCode == 403 || r.statusCode == 400 || r.statusCode == 429) {
          _routesBlocked = true;
        }
        return null;
      }
      final routes = <Map<String, dynamic>>[];
      for (final x in (jsonDecode(r.body)["routes"] as List?) ?? []) {
        final meters = (x["distanceMeters"] as num?)?.toInt() ?? 0;
        final secs = int.tryParse(
                (x["duration"] ?? "0s").toString().replaceAll("s", "")) ??
            0;
        routes.add(_route(x["polyline"]?["encodedPolyline"] ?? "", meters, secs));
      }
      return routes.isEmpty ? null : {"status": "OK", "routes": routes};
    } catch (e) {
      debugPrint("Routes API error: $e");
      return null;
    }
  }

  static const int maxRoutes = 4;

  /// FREE: public OSRM server (OpenStreetMap roads). Its "polyline" geometry
  /// uses the same encoding as Google, so decodePolyline works unchanged.
  /// Alternatives are generated as described in the class comment.
  Future<Map<String, dynamic>?> _osrm(double oLat, double oLng, double dLat,
      double dLng, bool alternatives,
      [List<List<double>> avoid = const []]) async {
    final first = await _osrmCall([
      [oLat, oLng],
      [dLat, dLng]
    ], alternatives);
    if (first.isEmpty) return null;
    if (!alternatives) return {"status": "OK", "routes": first};

    // Fastest route = reference for detour limits and waypoints.
    first.sort((a, b) => _secs(a).compareTo(_secs(b)));
    final base = first.first;
    final baseSecs = _secs(base);
    final basePts = _decode(_poly(base));
    final samples = _sample(basePts, 100);
    final kept = <Map<String, dynamic>>[...first];
    final keptPts = <List<List<double>>>[
      for (final r in first) _decode(_poly(r))
    ];

    // ---- candidate waypoints ----
    final waypoints = <List<double>>[];
    // 1. around incident hotspots that lie on the fastest route
    for (final h in avoid.take(3)) {
      int bi = -1;
      double bd = double.infinity;
      for (int i = 0; i < samples.length; i++) {
        final d = _dist(samples[i], h);
        if (d < bd) {
          bd = d;
          bi = i;
        }
      }
      if (bi < 0 || bd > 300) continue; // not on this route
      final dir = _direction(samples, bi);
      waypoints.add(_offset(h, dir, 500));
      waypoints.add(_offset(h, dir, -500));
    }
    // 2. side routes at 1/3, 1/2, 2/3 of the way
    final baseMeters = _meters(base).toDouble();
    final off = (baseMeters * 0.18).clamp(350.0, 1500.0);
    if (baseMeters > 400 && samples.length > 4) {
      for (final f in [0.33, 0.5, 0.66]) {
        final i =
            (samples.length * f).floor().clamp(0, samples.length - 1).toInt();
        final dir = _direction(samples, i);
        waypoints.add(_offset(samples[i], dir, off));
        waypoints.add(_offset(samples[i], dir, -off));
      }
    }

    // ---- route through each waypoint (4 at a time) ----
    for (int start = 0; start < waypoints.length; start += 4) {
      if (kept.length >= maxRoutes) break;
      final batch = waypoints.skip(start).take(4).toList();
      final results = await Future.wait(
          batch.map((w) => _viaClean(oLat, oLng, w, dLat, dLng)));
      for (final r in results) {
        if (r == null || kept.length >= maxRoutes) continue;
        final secs = _secs(r);
        final limit = math.max(baseSecs * 1.6, baseSecs + 600.0);
        if (secs > limit) continue; // detour too long
        final pts = _decode(_poly(r));
        if (keptPts.any((k) => _overlap(pts, k) > 0.8)) continue; // same road
        kept.add(r);
        keptPts.add(pts);
      }
    }

    // Fastest first (like Google's first route).
    kept.sort((a, b) => _secs(a).compareTo(_secs(b)));
    return {"status": "OK", "routes": kept};
  }

  /// Route origin -> waypoint -> destination without an "out-and-back"
  /// detour near the waypoint (re-routes through the detour start, max 2x).
  Future<Map<String, dynamic>?> _viaClean(
      double oLat, double oLng, List<double> w, double dLat, double dLng) async {
    var wp = w;
    for (int k = 0; k < 3; k++) {
      final r = await _osrmCall([
        [oLat, oLng],
        wp,
        [dLat, dLng]
      ], false);
      if (r.isEmpty) return null;
      final spur = _outAndBack(_decode(_poly(r.first)), wp);
      if (spur == null) return r.first;
      wp = spur;
    }
    return null;
  }

  // ---------------- geometry helpers ([lat, lng]) ----------------
  static int _secs(Map<String, dynamic> r) =>
      (r["legs"][0]["duration"]["value"] as num).toInt();
  static int _meters(Map<String, dynamic> r) =>
      (r["legs"][0]["distance"]["value"] as num).toInt();
  static String _poly(Map<String, dynamic> r) =>
      r["overview_polyline"]["points"] as String;

  static double _dist(List<double> a, List<double> b) {
    const rr = 6371000.0;
    final dLat = (b[0] - a[0]) * math.pi / 180;
    final dLng = (b[1] - a[1]) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a[0] * math.pi / 180) *
            math.cos(b[0] * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * rr * math.asin(math.sqrt(h));
  }

  /// Google / OSRM encoded polyline -> [lat, lng] points.
  static List<List<double>> _decode(String s) {
    final out = <List<double>>[];
    int i = 0, lat = 0, lng = 0;
    while (i < s.length) {
      int b, shift = 0, res = 0;
      do {
        b = s.codeUnitAt(i++) - 63;
        res |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && i < s.length);
      lat += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);
      shift = 0;
      res = 0;
      if (i >= s.length) break;
      do {
        b = s.codeUnitAt(i++) - 63;
        res |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && i < s.length);
      lng += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);
      out.add([lat / 1e5, lng / 1e5]);
    }
    return out;
  }

  /// Points every [step] metres along the line.
  static List<List<double>> _sample(List<List<double>> g, double step) {
    if (g.isEmpty) return [];
    final out = <List<double>>[g.first];
    double carry = 0;
    for (int i = 1; i < g.length; i++) {
      final seg = _dist(g[i - 1], g[i]);
      if (seg == 0) continue;
      double pos = step - carry;
      while (pos <= seg) {
        final f = pos / seg;
        out.add([
          g[i - 1][0] + (g[i][0] - g[i - 1][0]) * f,
          g[i - 1][1] + (g[i][1] - g[i - 1][1]) * f
        ]);
        pos += step;
      }
      carry = (carry + seg) % step;
    }
    return out;
  }

  /// Direction (east, north in metres) of the line around sample [i].
  static List<double> _direction(List<List<double>> s, int i) {
    final a = s[math.max(0, i - 2)];
    final b = s[math.min(s.length - 1, i + 2)];
    final cosLat = math.cos(a[0] * math.pi / 180);
    return [(b[1] - a[1]) * 111320 * cosLat, (b[0] - a[0]) * 110540];
  }

  /// Point [m] metres to the LEFT (m > 0) or RIGHT (m < 0) of direction.
  static List<double> _offset(List<double> p, List<double> dir, double m) {
    final len = math.sqrt(dir[0] * dir[0] + dir[1] * dir[1]);
    if (len == 0) return p;
    final px = -dir[1] / len, py = dir[0] / len; // perpendicular (left)
    final cosLat = math.cos(p[0] * math.pi / 180);
    return [p[0] + py * m / 110540, p[1] + px * m / (111320 * cosLat)];
  }

  /// Start of an "out-and-back" detour near [w] (the route drives down a
  /// road and returns the same way), or null if the route is clean.
  static List<double>? _outAndBack(List<List<double>> g, List<double> w) {
    final p = _sample(g, 20);
    for (int i = 0; i < p.length; i++) {
      if (_dist(p[i], w) > 800) continue;
      for (int j = p.length - 1; j > i + 8; j--) {
        if (_dist(p[i], p[j]) > 15) continue;
        bool back = true;
        for (int k = 1; k <= 3; k++) {
          if (i + k >= j - k || _dist(p[i + k], p[j - k]) > 20) {
            back = false;
            break;
          }
        }
        if (back) return p[i];
      }
    }
    return null;
  }

  /// Share of route [a] that runs on route [b] (0..1).
  static double _overlap(List<List<double>> a, List<List<double>> b) {
    final sa = _sample(a, 60), sb = _sample(b, 60);
    if (sa.isEmpty) return 1;
    int n = 0;
    for (final p in sa) {
      if (sb.any((q) => _dist(p, q) < 40)) n++;
    }
    return n / sa.length;
  }

  Future<List<Map<String, dynamic>>> _osrmCall(
      List<List<double>> points, bool alternatives) async {
    try {
      final coords = points.map((p) => "${p[1]},${p[0]}").join(";");
      final url = "https://router.project-osrm.org/route/v1/driving/$coords"
          "?overview=full&geometries=polyline"
          "${alternatives ? "&alternatives=3" : ""}";
      final r = await http.get(Uri.parse(url),
          headers: {"User-Agent": "SafeCity-FYP/1.0 (Flutter app)"});
      if (r.statusCode != 200) {
        debugPrint("OSRM ${r.statusCode}: ${r.body}");
        return [];
      }
      final data = jsonDecode(r.body);
      if (data["code"] != "Ok") return [];
      final out = <Map<String, dynamic>>[];
      for (final x in (data["routes"] as List?) ?? []) {
        out.add(_route(
          (x["geometry"] ?? "").toString(),
          (x["distance"] as num?)?.round() ?? 0,
          (x["duration"] as num?)?.round() ?? 0,
        ));
      }
      return out;
    } catch (e) {
      debugPrint("OSRM error: $e");
      return [];
    }
  }
}
