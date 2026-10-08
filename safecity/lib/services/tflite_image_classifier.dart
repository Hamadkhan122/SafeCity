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
// 4. Screen-texture model - screen_texture.tflite (small CNN, 0.5 MB)
//    Looks at 8 small 128x128 patches of the ORIGINAL full-resolution photo.
//    A photo taken of a laptop / phone / TV screen shows the screen's pixel
//    grid and moire (wavy colour bands) at full resolution, whatever picture
//    is shown on the screen. Score = mean of the 3 highest patches; only a
//    very confident score (>= textureMin) counts as "screen" (rejected as
//    "may show a screen", no strike).
//
// 5. Screen device detector - device_yolov8n.tflite (see
//    screen_device_detector.dart): is a laptop / TV / phone / keyboard
//    visible in the photo?
//
// 6. Fight-pair model - fight_pair.tflite (MobileNetV2 + 1 output, 4.5 MB)
//    When the pose rule finds two people in contact, the part of the photo
//    with those two people (upper body) is checked: friendly contact
//    (handshake, hug, high five, dancing) or a real fight? Trained on photos
//    of handshakes / hugs / high fives / dancing vs fights
//    (AI/scripts_v2/30_fight_pair_classifier.py).
//
// SCREEN DECISION (evidence based). The picture model's "screen" score alone
// was too sensitive on hazy / misty real photos (live fight photos were
// rejected), so a photo counts as a screen photo only when:
//   a) the picture model is very sure (screen >= 0.90), or
//   b) a laptop / TV / phone / keyboard is visible AND screen >= 0.30, or
//   c) the texture model finds a pixel grid / moire AND screen >= 0.30.
// Otherwise the screen score is capped below the reject limit and the
// category score is measured without the "screen" share.
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
import 'screen_device_detector.dart';

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

  static const _fightPairAsset = "assets/models/fight_pair.tflite";
  static Interpreter? _fightPairInterpreter;

  /// Fight-pair score 0..1 for the two people in [box] (photo-relative).
  static Future<double> _fightPair(img.Image photo, List<double> box) async {
    final it = _fightPairInterpreter ??= await Interpreter.fromAsset(_fightPairAsset);
    // Crop and its mirror image, averaged (as in testing).
    var sum = 0.0;
    for (final mirror in const [false, true]) {
      final input = _pairCrop(photo, box, mirror: mirror);
      final out = [List<double>.filled(1, 0.0)];
      it.run(input.buffer, out);
      sum += out[0][0];
    }
    return (sum / 2).clamp(0.0, 1.0).toDouble();
  }

  static const _textureAsset = "assets/models/screen_texture.tflite";
  static const double textureMin = 0.90; // ~1.4 % of real photos reach this

  // Screen decision limits (see SCREEN DECISION above).
  static const double screenSureMin = 0.90; // picture model alone
  static const double screenWithEvidenceMin = 0.30; // with device / texture
  static Interpreter? _textureInterpreter;

  static Future<double> _textureScore(List<Float32List> patches) async {
    final it = _textureInterpreter ??= await Interpreter.fromAsset(_textureAsset);
    final scores = <double>[];
    for (final p in patches) {
      final out = [List<double>.filled(1, 0.0)];
      it.run(p.buffer, out);
      scores.add(out[0][0]);
    }
    if (scores.isEmpty) return 0;
    scores.sort((a, b) => b.compareTo(a));
    final top = scores.take(3).toList();
    return top.reduce((a, b) => a + b) / top.length;
  }

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
    // The letterboxed 320 x 320 input is needed for every photo (device
    // detector) and for Fight (pose model).
    final prep = await Isolate.run(() => _preprocess(bytes, 224, true));
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
    double texture = 0;
    if (prep.patches.isNotEmpty) {
      try {
        texture = await _textureScore(prep.patches);
      } catch (e) {
        texture = 0; // texture model unavailable -> picture model only
      }
    }
    // Screen device (laptop / TV / phone / keyboard) visible in the photo?
    double deviceScore = 0;
    String? device;
    if (prep.pose != null) {
      try {
        final d = await ScreenDeviceDetector.analyze(prep.pose!);
        deviceScore = d.score;
        device = d.device;
      } catch (e) {
        deviceScore = 0; // detector unavailable -> other checks only
      }
    }

    // Evidence-based screen decision.
    final modelScreen = probs["screen"] ?? 0.0;
    double screenP;
    String screenEvidence = "";
    if (modelScreen >= screenSureMin) {
      screenP = modelScreen; // clearly a photo of a screen
    } else if (device != null && modelScreen >= screenWithEvidenceMin) {
      screenP = math.max(modelScreen, 0.55); // rejected; strike from 0.60
      screenEvidence = device;
    } else if (texture >= textureMin && modelScreen >= screenWithEvidenceMin) {
      screenP = 0.55; // rejected, no strike
      screenEvidence = "screen pixel pattern";
    } else {
      // No evidence: not treated as a screen photo (kept below the 0.50
      // reject limit so it is still visible in the AI Test Lab).
      screenP = math.min(modelScreen, 0.45);
    }
    final isScreen = screenP >= AiveService.screenRejectMin;
    // When the photo is not a screen photo, measure the category without the
    // share the model gave to "screen" (otherwise a hazy photo of a real
    // accident loses its accident score to the screen class).
    double cat(String label) {
      final p = probs[label] ?? 0.0;
      if (isScreen || modelScreen <= 0 || modelScreen >= 1) return p;
      return (p / (1 - modelScreen)).clamp(0.0, 1.0).toDouble();
    }
    final personP = probs["person"] ?? 0.0;

    double? raw;
    double? poseScore;
    double? pairScore;
    bool grab = false;
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
          grab = p.grab;
          if ((p.score >= AiveService.fightPassMin || p.grab) && p.pair != null) {
            try {
              pairScore = await _fightPair(prep.small, p.pair!);
            } catch (e) {
              pairScore = null; // model unavailable -> pose rule only
            }
          }
          // Contact pose counts only when the fight-pair model agrees that it
          // is a fight and not a handshake / hug.
          final poseFight = AiveService.poseFight(p.score, p.grab, pairScore);
          raw = math.max(raw, poseFight ? math.max(p.score, pairScore ?? 0.0) : 0.0);
        } catch (e) {
          // pose model unavailable -> keep the incident model's result
        }
      }
    } else if (_incidentLabelFor.containsKey(category)) {
      raw = cat(_incidentLabelFor[category]!);
    }

    return ImageAnalysis(
      categoryScore: raw,
      rawProbability: raw,
      screenProbability: screenP,
      screenEvidence: screenEvidence,
      personProbability: personP,
      topLabel: topLabel,
      topProbability: topP,
      usesFloor: category == "Fight" || category == "Harassment",
      probabilities: {
        ...probs,
        if (h.containsKey("harassment"))
          "violence (harassment model)": h["harassment"]!,
        if (poseScore != null) "fight pose": poseScore,
        if (pairScore != null) "fight pair": pairScore,
        if (poseScore != null) "fight grab": grab ? 1.0 : 0.0,
        "screen texture": texture,
        "screen device${device != null ? " ($device)" : ""}": deviceScore,
      },
    );
  }
}

/// Photo -> [1, size, size, 3] float32 RGB 0..255 (whole photo resized to
/// size x size with area averaging, like the training images) and the
/// letterboxed 320 x 320 input of the pose model / device detector.
({Float32List input, PoseInput? pose, List<Float32List> patches, img.Image small})? _preprocess(
    Uint8List bytes, int size, bool withPose) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  var upright = img.bakeOrientation(decoded); // fix camera EXIF rotation
  final patches = _texturePatches(upright); // full resolution, before resizing
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
  return (
    input: input,
    pose: withPose ? PoseFightDetector.prepare(upright) : null,
    patches: patches,
    small: upright,
  );
}

/// Crop of the two people found by the pose rule, like the training crops of
/// the fight-pair model: their joint box, upper 65 % (heads, arms, upper
/// bodies), 8 % margin, resized to 224 x 224, raw RGB 0..255.
Float32List _pairCrop(img.Image photo, List<double> box, {bool mirror = false}) {
  final w = photo.width.toDouble(), h = photo.height.toDouble();
  var x1 = box[0] * w, y1 = box[1] * h, x2 = box[2] * w, y2 = box[3] * h;
  y2 = y1 + 0.65 * (y2 - y1);
  final px = 0.08 * (x2 - x1), py = 0.08 * (y2 - y1);
  x1 = math.max(0.0, x1 - px);
  y1 = math.max(0.0, y1 - py);
  x2 = math.min(w, x2 + px);
  y2 = math.min(h, y2 + py);
  final int cx = math.min(x1.round(), photo.width - 1);
  final int cy = math.min(y1.round(), photo.height - 1);
  final int cw = math.max(1, math.min((x2 - x1).round(), photo.width - cx));
  final int ch = math.max(1, math.min((y2 - y1).round(), photo.height - cy));
  final crop = img.copyCrop(photo, x: cx, y: cy, width: cw, height: ch);
  final r = img.copyResize(crop, width: 224, height: 224, interpolation: img.Interpolation.average);
  final out = Float32List(224 * 224 * 3);
  var i = 0;
  for (var y = 0; y < 224; y++) {
    for (var x = 0; x < 224; x++) {
      final p = r.getPixel(mirror ? 223 - x : x, y);
      out[i++] = (p.rNormalized * 255.0).toDouble();
      out[i++] = (p.gNormalized * 255.0).toDouble();
      out[i++] = (p.bNormalized * 255.0).toDouble();
    }
  }
  return out;
}

/// 8 patches of 128 x 128 pixels from the middle 70 % of the ORIGINAL photo
/// (4 x 2 grid), raw RGB 0..255, for the screen-texture model.
List<Float32List> _texturePatches(img.Image photo) {
  const p = 128;
  final w = photo.width, h = photo.height;
  if (w < 600 || h < 600) return const [];
  final out = <Float32List>[];
  final x0 = (w * 0.15).round(), y0 = (h * 0.15).round();
  final spanX = (w * 0.7).round() - p, spanY = (h * 0.7).round() - p;
  for (var j = 0; j < 2; j++) {
    for (var i = 0; i < 4; i++) {
      final px = x0 + (spanX * i / 3).round();
      final py = y0 + (spanY * j).round();
      final buf = Float32List(p * p * 3);
      var k = 0;
      for (var y = 0; y < p; y++) {
        for (var x = 0; x < p; x++) {
          final c = photo.getPixel(px + x, py + y);
          buf[k++] = (c.rNormalized * 255.0).toDouble();
          buf[k++] = (c.gNormalized * 255.0).toDouble();
          buf[k++] = (c.bNormalized * 255.0).toDouble();
        }
      }
      out.add(buf);
    }
  }
  return out;
}
