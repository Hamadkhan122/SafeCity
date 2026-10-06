// SafeCity - Screen device check (is a laptop / TV / phone visible?)
// ==================================================================
// Used by the screen (recapture) check. The incident model's "screen" class
// alone is not reliable on hazy / misty outdoor photos: low contrast looks
// like a photographed screen to it. So a photo is only rejected as a screen
// photo when there is visible EVIDENCE, and this detector gives that
// evidence: it finds a laptop, a TV / monitor, a mobile phone or a keyboard
// in the photo.
//
// Model: YOLOv8n object detector (Ultralytics, free, COCO 80 classes),
//   assets/models/device_yolov8n.tflite
// Input : the same letterboxed [1, 3, 320, 320] float32 RGB 0..1 input as the
//   pose model (PoseFightDetector.prepare), so the photo is prepared once.
// Output: [1, 84, 2100]  per candidate: cx, cy, w, h (relative to 320) and
//   80 class scores. COCO ids used: 62 tv, 63 laptop, 66 keyboard,
//   67 cell phone.
// Score = highest class score of a device box covering at least 2 % of the
// photo (0 = no device). Tested: 0 of 457 live / incident photos had a device
// >= 0.25; 24-67 % of our photos of screens show the device clearly.

import 'package:tflite_flutter/tflite_flutter.dart';

import 'pose_fight_detector.dart';

class ScreenDeviceDetector {
  ScreenDeviceDetector._();

  static const asset = "assets/models/device_yolov8n.tflite";
  static const size = 320;
  static const double minScore = 0.25;
  static const double minArea = 0.02; // part of the photo the device covers

  static const Map<int, String> devices = {
    62: "TV / monitor screen",
    63: "laptop",
    66: "laptop", // keyboard = laptop
    67: "mobile phone",
  };

  static Interpreter? _interpreter;

  /// Device score 0..1 and the name of the device found (null = none).
  static Future<({double score, String? device})> analyze(PoseInput input) async {
    final it = _interpreter ??= await Interpreter.fromAsset(asset);
    final out = List.generate(
        1, (_) => List.generate(84, (_) => List<double>.filled(2100, 0.0)));
    it.run(input.data.buffer, out);
    final y = out[0];
    final photoArea = (input.w * input.h).toDouble();
    var best = 0.0;
    String? name;
    devices.forEach((cls, label) {
      final row = y[4 + cls];
      for (var j = 0; j < 2100; j++) {
        final s = row[j];
        if (s < minScore || s <= best) continue;
        final area = (y[2][j] * size) * (y[3][j] * size) / photoArea;
        if (area < minArea) continue;
        best = s;
        name = label;
      }
    });
    return (score: best, device: name);
  }
}
