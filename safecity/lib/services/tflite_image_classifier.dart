// SafeCity - On-device image classifier for AIVE (TensorFlow Lite)
// =================================================================
// Plugs into AiveService through the ImageClassifier interface.
// Runs fully on the phone: free, no server, works offline.
//
// Two models, both MobileNetV2, both take the SAME input:
//   [1, 224, 224, 3] float32, RGB 0..255 (normalisation is inside the model)
//
// 1. Incident model (v3) - incident_mobilenetv2.tflite
//    output [1, 7], order in incident_labels.txt:
//      accident, fighting, fire, normal, road_damage, screen  (softmax)
//      person                                                 (sigmoid)
//    "normal" = no incident in the photo (street, room, objects, blank ...)
//    "screen" = photo taken OF a laptop / monitor / phone screen
//               (e.g. a Google image photographed from a laptop)
//    "person" = separate yes/no output: are there people in the photo?
//               (needed for Fight / Harassment - a wall or cup is rejected)
//    Used for Accident, Fire, Road Damage directly, for Fight together with
//    the pose model, and for the screen (recapture) check on EVERY photo.
//
// 2. Harassment model (v2) - harassment_mobilenetv2.tflite
//    output [1, 2] softmax, order in harassment_labels.txt (normal, harassment)
//    Used for the Harassment category.
//
// 3. Pose model - pose_yolov8n.tflite (see pose_fight_detector.dart)
//    Finds people + body keypoints. Used for Fight: two people close together
//    in a punching / pushing / fighting-guard pose. Fight confidence =
//    max(incident "fighting", fight pose).
//
// Resizing uses area averaging (like the training pipeline). Plain linear
// sampling of a 12 MP camera photo down to 224 px skips most pixels and
// produces noisy, aliased input the models were never trained on.

import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'aive_service.dart';
import 'pose_fight_detector.dart';

class _Model {
  final String modelAsset;
  final String labelsAsset;
  const _Model(this.modelAsset, this.labelsAsset);
}

class TfliteImageClassifier implements ImageClassifier {
  const TfliteImageClassifier();

  static const _incident = _Model(
    "assets/models/incident_mobilenetv2.tflite",
    "assets/models/incident_labels.txt",
  );
  static const _harassment = _Model(
    "assets/models/harassment_mobilenetv2.tflite",
    "assets/models/harassment_labels.txt",
  );

  /// Report category -> incident-model label that confirms it.
  static const Map<String, String> _incidentLabelFor = {
    "Accident": "accident",
    "Fire": "fire",
    "Road Damage": "road_damage",
    "Fight": "fighting",
  };

  // Models are loaded once and reused for every report.
  static final Map<String, Interpreter> _interpreters = {};
  static final Map<String, List<String>> _labels = {};

  static Future<Map<String, double>> _run(_Model m, Float32List input) async {
    final interpreter = _interpreters[m.modelAsset] ??=
        await Interpreter.fromAsset(m.modelAsset);
    final labels = _labels[m.labelsAsset] ??=
        (await rootBundle.loadString(m.labelsAsset))
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

    final output = [List<double>.filled(labels.length, 0.0)];
    interpreter.run(input.buffer, output);

    return {
      for (var i = 0; i < labels.length; i++)
        labels[i]: output[0][i].clamp(0.0, 1.0).toDouble(),
    };
  }

  @override
  Future<ImageAnalysis?> analyze(String category, File image) async {
    // Decode + resize in a background isolate so the UI does not freeze.
    final bytes = await image.readAsBytes();
    final withPose = category == "Fight";
    final prep = await Isolate.run(() => _preprocess(bytes, 224, withPose));
    if (prep == null) return null; // unreadable photo
    final input = prep.input;

    // Incident model runs on every photo (category + screen check).
    final probs = await _run(_incident, input);
    String topLabel = "normal";
    double topP = 0;
    probs.forEach((k, v) {
      if (k == "person") return; // separate yes/no output, not a class
      if (v > topP) {
        topP = v;
        topLabel = k;
      }
    });
    final screenP = probs["screen"] ?? 0.0;
    final personP = probs["person"] ?? 0.0;

    double? raw;
    double? poseScore;
    Map<String, double> h = const {};
    if (category == "Harassment") {
      h = await _run(_harassment, input);
      raw = h["harassment"] ?? 0.0;
    } else if (category == "Fight") {
      // Fight = incident model "fighting" or the fight-pose check.
      // (The harassment model is not used here: on our tests it also called
      // hugs and handshakes violent, 13% of such photos.)
      raw = probs["fighting"] ?? 0.0;
      if (prep.pose != null) {
        try {
          final p = await PoseFightDetector.analyze(prep.pose!);
          poseScore = p.score;
          raw = math.max(raw, p.score);
        } catch (e) {
          // pose model unavailable -> keep the other two models' result
        }
      }
    } else if (_incidentLabelFor.containsKey(category)) {
      raw = probs[_incidentLabelFor[category]] ?? 0.0;
    }

    return ImageAnalysis(
      categoryScore: raw,
      rawProbability: raw,
      screenProbability: screenP,
      personProbability: personP,
      topLabel: topLabel,
      topProbability: topP,
      usesFloor: category == "Fight" || category == "Harassment",
      probabilities: {
        ...probs,
        if (h.containsKey("harassment"))
          "violence (harassment model)": h["harassment"]!,
        if (poseScore != null) "fight pose": poseScore,
      },
    );
  }
}

/// Photo -> [1, size, size, 3] float32 RGB 0..255 (whole photo resized to
/// size x size with area averaging, like the training images) and, for
/// Fight, the letterboxed input of the pose model.
({Float32List input, PoseInput? pose})? _preprocess(
    Uint8List bytes, int size, bool withPose) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  var upright = img.bakeOrientation(decoded); // fix camera EXIF rotation
  // Big camera photo -> max 896 px first (one averaging pass over the full
  // photo), then the model sizes are made from that smaller copy.
  final longSide = math.max(upright.width, upright.height);
  if (longSide > 896) {
    final k = 896 / longSide;
    upright = img.copyResize(
      upright,
      width: math.max(1, (upright.width * k).round()),
      height: math.max(1, (upright.height * k).round()),
      interpolation: img.Interpolation.average,
    );
  }
  final resized = img.copyResize(
    upright,
    width: size,
    height: size,
    interpolation: img.Interpolation.average,
  );

  final input = Float32List(size * size * 3);
  var i = 0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final p = resized.getPixel(x, y);
      input[i++] = (p.rNormalized * 255.0).toDouble();
      input[i++] = (p.gNormalized * 255.0).toDouble();
      input[i++] = (p.bNormalized * 255.0).toDouble();
    }
  }
  return (input: input, pose: withPose ? PoseFightDetector.prepare(upright) : null);
}
