// SafeCity - Free image storage (Cloudinary)
// ==========================================
// Replaces Firebase Storage (needs the paid Blaze plan).
// The captured report photo is uploaded straight from the app using an
// UNSIGNED upload preset (no backend, no API secret inside the app).
// The returned https link is saved in Firestore as "imageUrl", so every
// screen that shows report photos keeps working unchanged.
//
// SETUP (one time, free, no card):
//   1. Sign up at cloudinary.com -> Dashboard -> copy "Cloud name".
//   2. Settings -> Upload -> Upload presets -> Add upload preset
//      -> Signing mode: Unsigned -> Save -> copy the preset name.
//   3. Put both values below.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class CloudinaryService {
  static const String cloudName = "ba2ugj8w";
  static const String uploadPreset = "safecity_unsigned";
  static const String folder = "safecity/reports";

  static bool get isConfigured =>
      !cloudName.startsWith("YOUR_") && !uploadPreset.startsWith("YOUR_");

  /// Uploads [file] and returns a display-ready https URL
  /// (auto format/quality, max width 1080 -> less data for viewers).
  static Future<String> uploadReportImage(File file, String reportId) async {
    if (!isConfigured) {
      throw StateError("Cloudinary is not configured (cloudName / uploadPreset)");
    }

    final uri =
        Uri.parse("https://api.cloudinary.com/v1_1/$cloudName/image/upload");
    final publicId = reportId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

    final request = http.MultipartRequest("POST", uri)
      ..fields["upload_preset"] = uploadPreset
      ..fields["folder"] = folder
      ..fields["public_id"] = publicId
      ..files.add(await http.MultipartFile.fromPath("file", file.path));

    final streamed =
        await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw HttpException(
          "Cloudinary upload failed (${response.statusCode}): ${response.body}");
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final secureUrl = data["secure_url"] as String;

    // Same photo, optimised for viewing in the app.
    return secureUrl.replaceFirst(
        "/image/upload/", "/image/upload/f_auto,q_auto,w_1080/");
  }
}
