import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class PlacesService {
  static const String apiKey = "AIzaSyAU3UxNT9xlSea9G3iDbIYBDJDqGojSU5s";

  // ===============================
  // Nearby Places — Police, Hospital, Fire Station
  // ===============================
  Future<List<dynamic>> nearbyPlaces({
    required double latitude,
    required double longitude,
    required String type,
    int radius = 5000,
  }) async {
    try {
      final url =
          "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
          "?location=$latitude,$longitude"
          "&radius=$radius"
          "&type=$type"
          "&key=$apiKey";

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data["status"] != "OK") {
          debugPrint("nearbyPlaces status: ${data["status"]}");
          return [];
        }

        return data["results"];
      }

      return [];
    } catch (e) {
      debugPrint("nearbyPlaces error: $e");
      return [];
    }
  }

  // ===============================
  // Search Places — Autocomplete
  // ===============================
  Future<List<dynamic>> searchPlaces(String query) async {
    try {
      final url =
          "https://maps.googleapis.com/maps/api/place/autocomplete/json"
          "?input=$query"
          "&components=country:pk"
          "&language=en"
          "&key=$apiKey";

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data["status"] != "OK") {
          debugPrint("searchPlaces status: ${data["status"]}");
          return [];
        }

        return data["predictions"] ?? [];
      }

      return [];
    } catch (e) {
      debugPrint("searchPlaces error: $e");
      return [];
    }
  }

  // ===============================
  // Get Place Location — Place Details
  // ===============================
  Future<Map<String, dynamic>?> getPlaceLocation(String placeId) async {
    try {
      final url =
          "https://maps.googleapis.com/maps/api/place/details/json"
          "?place_id=$placeId"
          "&key=$apiKey";

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data["status"] != "OK") {
          debugPrint("getPlaceLocation status: ${data["status"]}");
          return null;
        }

        return data["result"];
      }

      return null;
    } catch (e) {
      debugPrint("getPlaceLocation error: $e");
      return null;
    }
  }

  Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    try {
      final url =
          "https://maps.googleapis.com/maps/api/place/details/json"
          "?place_id=$placeId"
          "&fields=name,formatted_address,rating,formatted_phone_number,opening_hours,geometry"
          "&key=$apiKey";

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data["status"] != "OK") {
          debugPrint("getPlaceDetails status: ${data["status"]}");
          return null;
        }

        return data["result"];
      }

      return null;
    } catch (e) {
      debugPrint("getPlaceDetails error: $e");
      return null;
    }
  }
}