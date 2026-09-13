import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class DirectionsService {
  static const String apiKey = "AIzaSyAU3UxNT9xlSea9G3iDbIYBDJDqGojSU5s";

  Future<Map<String, dynamic>?> getDirections({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    try {
      final url =
          "https://maps.googleapis.com/maps/api/directions/json"
          "?origin=$originLat,$originLng"
          "&destination=$destLat,$destLng"
          "&mode=driving"
          "&key=$apiKey";

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);

        if (json["status"] != "OK") {
          debugPrint("getDirections status: ${json["status"]}");
          return null;
        }

        if (json["routes"] == null || json["routes"].isEmpty) {
          return null;
        }

        return json;
      }

      return null;
    } catch (e) {
      debugPrint("getDirections error: $e");
      return null;
    }
  }
}