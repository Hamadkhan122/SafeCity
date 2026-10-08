import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Places: search, place details, nearby police / hospital / fire station.
///
/// Order:
///   1. Google Places (classic)  -> if refused (billing / legacy API off)
///   2. Google Places (New)      -> if refused
///   3. OpenStreetMap — FREE, no API key, no credit card:
///        search  : Nominatim
///        nearby  : Overpass API
/// Once a Google API is refused it is skipped for the rest of the session,
/// so the app does not waste time on it. Results are always converted to
/// the classic Google shape, so the screens don't change.
class PlacesService {
  static const String apiKey = "AIzaSyAU3UxNT9xlSea9G3iDbIYBDJDqGojSU5s";
  static const _newBase = "https://places.googleapis.com/v1";
  static const _osmHeaders = {"User-Agent": "SafeCity-FYP/1.0 (Flutter app)"};

  static bool _legacyBlocked = false;
  static bool _newBlocked = false;

  /// OpenStreetMap places by id (no "details" API needed for them).
  static final Map<String, Map<String, dynamic>> _osmCache = {};

  static Map<String, String> _newHeaders(String fieldMask) => {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": fieldMask,
      };

  static void _legacyFailed(String where, dynamic data) {
    debugPrint("$where Google status: ${data["status"]} "
        "${data["error_message"] ?? ""}");
    if (data["status"] == "REQUEST_DENIED" ||
        data["status"] == "OVER_QUERY_LIMIT") {
      _legacyBlocked = true;
    }
  }

  static void _newFailed(String where, http.Response r) {
    debugPrint("$where Google (New) ${r.statusCode}: ${r.body}");
    if (r.statusCode == 403 || r.statusCode == 400 || r.statusCode == 429) {
      _newBlocked = true;
    }
  }

  /// Google (New) place -> classic shape.
  static Map<String, dynamic> _fromNew(Map<String, dynamic> p) {
    final loc = p["location"] ?? {};
    return {
      "place_id": p["id"],
      "name": p["displayName"]?["text"] ?? "",
      "vicinity": p["shortFormattedAddress"] ?? p["formattedAddress"] ?? "",
      "formatted_address": p["formattedAddress"] ?? "",
      "formatted_phone_number": p["nationalPhoneNumber"],
      "rating": p["rating"],
      if (p["regularOpeningHours"] != null)
        "opening_hours": {"open_now": p["regularOpeningHours"]["openNow"]},
      "geometry": {
        "location": {"lat": loc["latitude"], "lng": loc["longitude"]},
      },
    };
  }

  // ===============================
  // Nearby Places — Police, Hospital, Fire Station
  // ===============================
  Future<List<dynamic>> nearbyPlaces({
    required double latitude,
    required double longitude,
    required String type,
    int radius = 5000,
  }) async {
    if (!_legacyBlocked) {
      try {
        final url = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
            "?location=$latitude,$longitude&radius=$radius&type=$type&key=$apiKey";
        final r = await http.get(Uri.parse(url));
        if (r.statusCode == 200) {
          final data = jsonDecode(r.body);
          if (data["status"] == "OK") return data["results"];
          if (data["status"] == "ZERO_RESULTS") return [];
          _legacyFailed("nearbyPlaces", data);
        }
      } catch (e) {
        debugPrint("nearbyPlaces error: $e");
      }
    }

    if (!_newBlocked) {
      try {
        final r = await http.post(
          Uri.parse("$_newBase/places:searchNearby"),
          headers: _newHeaders(
              "places.id,places.displayName,places.formattedAddress,"
              "places.shortFormattedAddress,places.location,"
              "places.nationalPhoneNumber,places.rating"),
          body: jsonEncode({
            "includedTypes": [type],
            "maxResultCount": 20,
            "rankPreference": "DISTANCE",
            "locationRestriction": {
              "circle": {
                "center": {"latitude": latitude, "longitude": longitude},
                "radius": radius.toDouble(),
              },
            },
          }),
        );
        if (r.statusCode == 200) {
          final places = (jsonDecode(r.body)["places"] as List?) ?? [];
          return places
              .map((p) => _fromNew(Map<String, dynamic>.from(p)))
              .toList();
        }
        _newFailed("nearbyPlaces", r);
      } catch (e) {
        debugPrint("nearbyPlaces (new) error: $e");
      }
    }

    return _osmNearby(latitude, longitude, type, radius);
  }

  // Overpass allows only ~2 requests at once, so SOS (3 types together)
  // used to get "too many requests". Requests now run one by one and are
  // cached for 10 minutes.
  static Future<void> _overpassQueue = Future.value();
  static final Map<String, List<dynamic>> _nearbyCache = {};
  static final Map<String, DateTime> _nearbyCacheTime = {};

  Future<List<dynamic>> _osmNearby(
      double lat, double lng, String type, int radius) {
    final key = "$type:${lat.toStringAsFixed(2)}:${lng.toStringAsFixed(2)}";
    final t = _nearbyCacheTime[key];
    if (t != null && DateTime.now().difference(t).inMinutes < 10) {
      return Future.value(_nearbyCache[key]!);
    }
    final job = _overpassQueue.then((_) async {
      var res = await _overpass(lat, lng, type, radius < 10000 ? 10000 : radius);
      // Overpass busy/empty -> Photon search near the user (also free).
      if (res.isEmpty) res = await _photonNearby(lat, lng, type);
      if (res.isNotEmpty) {
        _nearbyCache[key] = res;
        _nearbyCacheTime[key] = DateTime.now();
      }
      return res;
    });
    _overpassQueue = job.then((_) {}, onError: (_) {});
    return job;
  }

  Future<List<dynamic>> _overpass(
      double lat, double lng, String type, int radius) async {
    final around = "(around:$radius,$lat,$lng)";
    String filters;
    if (type == "hospital") {
      filters = 'nwr["amenity"~"^(hospital|clinic)\$"]$around;'
          'nwr["healthcare"="hospital"]$around;';
    } else if (type == "fire_station") {
      filters = 'nwr["amenity"="fire_station"]$around;'
          'nwr["emergency"="fire_station"]$around;'
          'nwr["name"~"Rescue 1122",i]$around;';
    } else {
      filters = 'nwr["amenity"="$type"]$around;';
    }
    final query = '[out:json][timeout:25];($filters);out center 25;';

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final r = await http.post(
          Uri.parse("https://overpass-api.de/api/interpreter"),
          headers: _osmHeaders,
          body: {"data": query},
        );
        if (r.statusCode == 429 || r.statusCode == 504) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        if (r.statusCode != 200) {
          debugPrint("Overpass ${r.statusCode}");
          return [];
        }
        return _parseOverpass(r.body, type);
      } catch (e) {
        debugPrint("Overpass error: $e");
      }
    }
    return [];
  }

  Future<List<dynamic>> _photonNearby(double lat, double lng, String type) async {
    final tag = type == "police"
        ? "amenity:police"
        : type == "hospital"
            ? "amenity:hospital"
            : "amenity:fire_station";
    final q = type == "police"
        ? "police station"
        : type == "hospital"
            ? "hospital"
            : "fire station rescue";
    try {
      final url = "https://photon.komoot.io/api/"
          "?q=${Uri.encodeQueryComponent(q)}&osm_tag=$tag"
          "&lat=$lat&lon=$lng&limit=15&lang=en";
      final r = await http.get(Uri.parse(url), headers: _osmHeaders);
      if (r.statusCode != 200) return [];
      final out = <Map<String, dynamic>>[];
      for (final f in (jsonDecode(r.body)["features"] as List?) ?? []) {
        final c = f["geometry"]?["coordinates"];
        if (c is! List || c.length < 2) continue;
        final pLat = (c[1] as num).toDouble(), pLng = (c[0] as num).toDouble();
        // keep only places within ~15 km
        if ((pLat - lat).abs() > 0.14 || (pLng - lng).abs() > 0.17) continue;
        final pr = Map<String, dynamic>.from(f["properties"] ?? {});
        final id = "osm_${pr["osm_type"] ?? "x"}_${pr["osm_id"] ?? out.length}";
        final address = [pr["street"], pr["city"]]
            .where((x) => x != null && x.toString().isNotEmpty)
            .join(", ");
        final place = <String, dynamic>{
          "place_id": id,
          "name": (pr["name"] ?? q).toString(),
          "vicinity": address,
          "formatted_address": address,
          "geometry": {
            "location": {"lat": pLat, "lng": pLng},
          },
        };
        _osmCache[id] = place;
        out.add(place);
      }
      return out;
    } catch (e) {
      debugPrint("Photon nearby error: $e");
      return [];
    }
  }

  List<dynamic> _parseOverpass(String body, String type) {
    final out = <Map<String, dynamic>>[];
    for (final e in (jsonDecode(body)["elements"] as List?) ?? []) {
      final pLat = (e["lat"] ?? e["center"]?["lat"]) as num?;
      final pLng = (e["lon"] ?? e["center"]?["lon"]) as num?;
      if (pLat == null || pLng == null) continue;
      final tags = Map<String, dynamic>.from(e["tags"] ?? {});
      final fallbackName = type == "police"
          ? "Police Station"
          : type == "hospital"
              ? "Hospital"
              : "Fire Station";
      final address = [
        tags["addr:street"],
        tags["addr:city"],
      ].where((x) => x != null && x.toString().isNotEmpty).join(", ");
      final id = "osm_${e["type"]}_${e["id"]}";
      final place = <String, dynamic>{
        "place_id": id,
        "name": (tags["name:en"] ?? tags["name"] ?? fallbackName).toString(),
        "vicinity": address,
        "formatted_address": address,
        "formatted_phone_number": tags["phone"] ?? tags["contact:phone"],
        "geometry": {
          "location": {"lat": pLat.toDouble(), "lng": pLng.toDouble()},
        },
      };
      _osmCache[id] = place;
      out.add(place);
    }
    return out;
  }

  // ===============================
  // Search Places — Autocomplete
  // ===============================
  Future<List<dynamic>> searchPlaces(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    if (!_legacyBlocked) {
      try {
        final url = "https://maps.googleapis.com/maps/api/place/autocomplete/json"
            "?input=${Uri.encodeQueryComponent(q)}"
            "&components=country:pk&language=en&key=$apiKey";
        final r = await http.get(Uri.parse(url));
        if (r.statusCode == 200) {
          final data = jsonDecode(r.body);
          if (data["status"] == "OK") return data["predictions"] ?? [];
          if (data["status"] != "ZERO_RESULTS") _legacyFailed("searchPlaces", data);
        }
      } catch (e) {
        debugPrint("searchPlaces error: $e");
      }
    }

    if (!_newBlocked) {
      try {
        final r = await http.post(
          Uri.parse("$_newBase/places:autocomplete"),
          headers: {"Content-Type": "application/json", "X-Goog-Api-Key": apiKey},
          body: jsonEncode({
            "input": q,
            "includedRegionCodes": ["pk"],
            "languageCode": "en",
          }),
        );
        if (r.statusCode == 200) {
          final out = <Map<String, dynamic>>[];
          for (final s in (jsonDecode(r.body)["suggestions"] as List?) ?? []) {
            final p = s["placePrediction"];
            if (p == null) continue;
            out.add({
              "place_id": p["placeId"],
              "description": p["text"]?["text"] ?? "",
            });
          }
          if (out.isNotEmpty) return out;
        } else {
          _newFailed("searchPlaces", r);
        }
      } catch (e) {
        debugPrint("searchPlaces (new) error: $e");
      }
    }

    return _osmSearch(q);
  }

  /// FREE search. Photon (komoot) understands half-typed words, so it
  /// works like autocomplete; Nominatim is the backup. Results carry
  /// lat/lng directly, so the screens drop the pin without a details call.
  Future<List<dynamic>> _osmSearch(String q) async {
    final photon = await _photon(q);
    if (photon.isNotEmpty) return photon;
    return _nominatim(q);
  }

  Future<List<dynamic>> _photon(String q) async {
    try {
      // Biased to Abbottabad, limited to Pakistan's bounding box.
      final url = "https://photon.komoot.io/api/"
          "?q=${Uri.encodeQueryComponent(q)}"
          "&limit=8&lang=en&lat=34.1688&lon=73.2215"
          "&bbox=60.87,23.69,77.84,37.08";
      final r = await http.get(Uri.parse(url), headers: _osmHeaders);
      if (r.statusCode != 200) {
        debugPrint("Photon ${r.statusCode}");
        return [];
      }
      final out = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final f in (jsonDecode(r.body)["features"] as List?) ?? []) {
        final pr = Map<String, dynamic>.from(f["properties"] ?? {});
        if ((pr["countrycode"] ?? "PK").toString().toUpperCase() != "PK") {
          continue;
        }
        final c = f["geometry"]?["coordinates"];
        if (c is! List || c.length < 2) continue;
        final parts = <String>[];
        for (final k in ["name", "street", "district", "city", "county", "state"]) {
          final v = (pr[k] ?? "").toString().trim();
          if (v.isNotEmpty && !parts.contains(v)) parts.add(v);
          if (parts.length == 3) break;
        }
        if (parts.isEmpty) continue;
        final desc = parts.join(", ");
        if (!seen.add(desc)) continue;
        out.add({
          "description": desc,
          "lat": (c[1] as num).toDouble(),
          "lng": (c[0] as num).toDouble(),
        });
      }
      return out;
    } catch (e) {
      debugPrint("Photon error: $e");
      return [];
    }
  }

  Future<List<dynamic>> _nominatim(String q) async {
    try {
      final url = "https://nominatim.openstreetmap.org/search"
          "?q=${Uri.encodeQueryComponent(q)}"
          "&format=jsonv2&countrycodes=pk&limit=6&accept-language=en";
      final r = await http.get(Uri.parse(url), headers: _osmHeaders);
      if (r.statusCode != 200) {
        debugPrint("Nominatim ${r.statusCode}");
        return [];
      }
      final out = <Map<String, dynamic>>[];
      for (final p in (jsonDecode(r.body) as List)) {
        final lat = double.tryParse(p["lat"].toString());
        final lng = double.tryParse(p["lon"].toString());
        if (lat == null || lng == null) continue;
        // Keep it short: first 3 parts of the address.
        final full = (p["display_name"] ?? q).toString().split(", ");
        out.add({
          "description": full.take(3).join(", "),
          "lat": lat,
          "lng": lng,
        });
      }
      return out;
    } catch (e) {
      debugPrint("Nominatim error: $e");
      return [];
    }
  }

  // ===============================
  // Place location / details
  // ===============================
  Future<Map<String, dynamic>?> getPlaceLocation(String placeId) =>
      getPlaceDetails(placeId);

  Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    if (placeId.startsWith("osm_")) return _osmCache[placeId];

    if (!_legacyBlocked) {
      try {
        final url = "https://maps.googleapis.com/maps/api/place/details/json"
            "?place_id=$placeId"
            "&fields=name,formatted_address,rating,formatted_phone_number,opening_hours,geometry"
            "&key=$apiKey";
        final r = await http.get(Uri.parse(url));
        if (r.statusCode == 200) {
          final data = jsonDecode(r.body);
          if (data["status"] == "OK") return data["result"];
          _legacyFailed("getPlaceDetails", data);
        }
      } catch (e) {
        debugPrint("getPlaceDetails error: $e");
      }
    }

    if (!_newBlocked) {
      try {
        final r = await http.get(
          Uri.parse("$_newBase/places/$placeId"),
          headers: _newHeaders(
              "id,displayName,formattedAddress,shortFormattedAddress,location,"
              "rating,nationalPhoneNumber,regularOpeningHours"),
        );
        if (r.statusCode == 200) {
          return _fromNew(Map<String, dynamic>.from(jsonDecode(r.body)));
        }
        _newFailed("getPlaceDetails", r);
      } catch (e) {
        debugPrint("getPlaceDetails (new) error: $e");
      }
    }
    return null;
  }
}
