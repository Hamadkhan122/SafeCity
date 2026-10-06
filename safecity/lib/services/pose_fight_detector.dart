// SafeCity - Fight detection from body poses (second opinion for Fight)
// =====================================================================
// The incident / violence models were trained mostly on CCTV footage, so a
// fight photographed with a phone (people close to the camera) is often
// missed. This detector finds every person and their body keypoints with
// YOLOv8n-pose (assets/models/pose_yolov8n.tflite, free, runs on the phone)
// and checks the pose of two people standing close together:
//   * arm reaching into the other person at head / chest height (punch, push)
//   * a kick by a standing person
//   * BOTH people in a fighting guard (fists up, elbows down), nobody sitting
// One person posing with raised fists next to a calm / sitting person is NOT
// a fight.
// Returns a score 0..1 (0 = no fight pose). Same rules as
// AI/scripts_v2/17_pose_fight_rule.py (tested: 7/8 posed fight photos pass,
// our fake 'one person posing' photos rejected).
//
// Model input : [1, 3, 320, 320] float32 RGB 0..1 (channels first),
//               photo letterboxed (grey 114 padding)
// Model output: [1, 56, 2100]  per candidate: cx, cy, w, h, person score,
//               17 keypoints x (x, y, visibility), all relative to 320.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class PoseInput {
  final Float32List data; // [3 * 320 * 320]
  final int offX, offY, w, h; // letterbox placement inside 320 x 320
  final double aspect; // photo width / height
  const PoseInput(this.data, this.offX, this.offY, this.w, this.h, this.aspect);
}

class _Person {
  final double x1, y1, x2, y2, score;
  final List<double> kp; // 17 * 3, x/y normalised to the photo (0..1)
  _Person(this.x1, this.y1, this.x2, this.y2, this.score, this.kp);
}

class _Pose {
  late double x1, y1, x2, y2, h, cx, cy, torso;
  bool raised = false, kick = false, seated = false;
  int guard = 0;
  final List<List<double>?> wristShoulder = []; // [wx, wy, sx, sy] (s may be missing)
}

class PoseFightDetector {
  PoseFightDetector._();

  static const asset = "assets/models/pose_yolov8n.tflite";
  static const size = 320;
  static Interpreter? _interpreter;

  /// Letterbox the decoded photo for the pose model (call in an isolate).
  static PoseInput prepare(img.Image photo) {
    final s = size / math.max(photo.width, photo.height);
    final w = math.max(1, (photo.width * s).round());
    final h = math.max(1, (photo.height * s).round());
    final r = img.copyResize(photo,
        width: w, height: h, interpolation: img.Interpolation.average);
    final ox = (size - w) ~/ 2, oy = (size - h) ~/ 2;
    final data = Float32List(3 * size * size)..fillRange(0, 3 * size * size, 114 / 255);
    const plane = size * size;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = r.getPixel(x, y);
        final i = (y + oy) * size + (x + ox);
        data[i] = p.rNormalized.toDouble();
        data[plane + i] = p.gNormalized.toDouble();
        data[2 * plane + i] = p.bNormalized.toDouble();
      }
    }
    return PoseInput(data, ox, oy, w, h, photo.width / photo.height);
  }

  /// Fight-pose score 0..1, the number of people found and the box of the
  /// two people that gave the score (x1, y1, x2, y2 relative to the photo,
  /// null when no pair was found). The box is checked by the fight-pair
  /// model (friendly contact such as a handshake vs a real fight).
  static Future<({double score, int people, List<double>? pair})> analyze(
      PoseInput input) async {
    final it = _interpreter ??= await Interpreter.fromAsset(asset);
    final out = List.generate(1, (_) => List.generate(56, (_) => List<double>.filled(2100, 0.0)));
    it.run(input.data.buffer, out);
    final people = _decode(out[0], input);
    final r = _rule(people, input.aspect);
    return (
      score: r.score,
      people: people.where((p) => p.score >= 0.5).length,
      pair: r.pair,
    );
  }

  static List<_Person> _decode(List<List<double>> y, PoseInput inp) {
    final cands = <_Person>[];
    for (var j = 0; j < 2100; j++) {
      final conf = y[4][j];
      if (conf < 0.25) continue;
      final cx = y[0][j] * size, cy = y[1][j] * size, bw = y[2][j] * size, bh = y[3][j] * size;
      final kp = List<double>.filled(51, 0);
      for (var k = 0; k < 17; k++) {
        kp[k * 3] = (y[5 + k * 3][j] * size - inp.offX) / inp.w;
        kp[k * 3 + 1] = (y[6 + k * 3][j] * size - inp.offY) / inp.h;
        kp[k * 3 + 2] = y[7 + k * 3][j];
      }
      cands.add(_Person((cx - bw / 2 - inp.offX) / inp.w, (cy - bh / 2 - inp.offY) / inp.h,
          (cx + bw / 2 - inp.offX) / inp.w, (cy + bh / 2 - inp.offY) / inp.h, conf, kp));
    }
    cands.sort((a, b) => b.score.compareTo(a.score));
    final keep = <_Person>[];
    for (final d in cands) {
      var ok = true;
      for (final k in keep) {
        final iw = math.max(0.0, math.min(d.x2, k.x2) - math.max(d.x1, k.x1));
        final ih = math.max(0.0, math.min(d.y2, k.y2) - math.max(d.y1, k.y1));
        final inter = iw * ih;
        final u = (d.x2 - d.x1) * (d.y2 - d.y1) + (k.x2 - k.x1) * (k.y2 - k.y1) - inter;
        if (u > 0 && inter / u > 0.5) {
          ok = false;
          break;
        }
      }
      if (ok) keep.add(d);
    }
    return keep;
  }

  static const _kv = 0.3;

  static List<double>? _pt(List<double> kp, int i, double ar) =>
      kp[i * 3 + 2] >= _kv ? [kp[i * 3] * ar, kp[i * 3 + 1]] : null;

  static _Pose _pose(_Person p, double ar) {
    final q = _Pose()
      ..x1 = p.x1 * ar
      ..y1 = p.y1
      ..x2 = p.x2 * ar
      ..y2 = p.y2;
    q.h = math.max(q.y2 - q.y1, 1e-3);
    q.cx = (q.x1 + q.x2) / 2;
    q.cy = (q.y1 + q.y2) / 2;
    final sh = [_pt(p.kp, 5, ar), _pt(p.kp, 6, ar)].whereType<List<double>>().toList();
    final hp = [_pt(p.kp, 11, ar), _pt(p.kp, 12, ar)].whereType<List<double>>().toList();
    double mean(List<List<double>> l) => l.map((e) => e[1]).reduce((a, b) => a + b) / l.length;
    q.torso = (sh.isNotEmpty && hp.isNotEmpty)
        ? math.max((mean(hp) - mean(sh)).abs(), 0.15 * q.h)
        : 0.3 * q.h;
    for (final arm in const [
      [5, 7, 9],
      [6, 8, 10]
    ]) {
      final s = _pt(p.kp, arm[0], ar), e = _pt(p.kp, arm[1], ar), w = _pt(p.kp, arm[2], ar);
      if (w != null) q.wristShoulder.add(s == null ? null : [w[0], w[1], s[0], s[1]]);
      if (s != null && w != null && w[1] < s[1] - 0.05 * q.torso) q.raised = true;
      if (s != null && e != null && w != null &&
          w[1] < e[1] - 0.2 * q.torso &&
          w[1] < s[1] + 0.4 * q.torso) {
        q.guard++;
      }
    }
    for (final leg in const [
      [15, 11, 16],
      [16, 12, 15]
    ]) {
      final a = _pt(p.kp, leg[0], ar), hip = _pt(p.kp, leg[1], ar), o = _pt(p.kp, leg[2], ar);
      if (a != null && hip != null && o != null &&
          a[1] < hip[1] + 1.0 * q.torso &&
          a[1] < o[1] - 0.8 * q.torso) {
        q.kick = true;
      }
    }
    // Sitting: knees at about hip height (cross-legged, on a chair).
    final kn = [_pt(p.kp, 13, ar), _pt(p.kp, 14, ar)].whereType<List<double>>().toList();
    if (hp.isNotEmpty && kn.isNotEmpty && mean(kn) - mean(hp) < 0.5 * q.torso) {
      q.seated = true;
    }
    return q;
  }

  static bool _strike(_Pose p, _Pose q) {
    final m = 0.05 * q.h, chest = q.y1 + 0.55 * (q.y2 - q.y1);
    for (final ws in p.wristShoulder) {
      if (ws == null) continue;
      final wx = ws[0], wy = ws[1], sx = ws[2], sy = ws[3];
      final reach = math.sqrt(math.pow(wx - sx, 2) + math.pow(wy - sy, 2)) / p.torso;
      final horiz = (wx - sx).abs() / p.torso;
      if (wx >= q.x1 - m && wx <= q.x2 + m && wy >= q.y1 && wy <= chest &&
          reach > 0.5 && horiz > 0.45 && wy < sy + 0.6 * p.torso) {
        return true;
      }
    }
    return false;
  }

  static ({double score, List<double>? pair}) _rule(List<_Person> people, double ar) {
    final ps = people
        .where((p) => p.score >= 0.5)
        .take(6)
        .map((p) => _pose(p, ar))
        .where((q) => q.h >= 0.2)
        .toList();
    var best = 0.0;
    var bestD = double.infinity;
    List<double>? pair;
    for (var a = 0; a < ps.length; a++) {
      for (var b = a + 1; b < ps.length; b++) {
        final pa = ps[a], pb = ps[b];
        final mh = (pa.h + pb.h) / 2;
        if (math.min(pa.h, pb.h) / math.max(pa.h, pb.h) < 0.5) continue;
        final d = math.sqrt(math.pow(pa.cx - pb.cx, 2) + math.pow(pa.cy - pb.cy, 2)) / mh;
        if (d > 1.3) continue;
        var s = 0.0;
        // Arm reaching into the other person (punch / push).
        if (_strike(pa, pb) || _strike(pb, pa)) s = math.max(s, 0.8);
        // Kick by a standing person.
        if ((pa.kick && !pa.seated) || (pb.kick && !pb.seated)) s = math.max(s, 0.8);
        // BOTH people in a fighting guard (one with both fists up), nobody
        // sitting. One person posing with fists next to a calm person is
        // not a fight.
        if (pa.guard > 0 && pb.guard > 0 &&
            math.max(pa.guard, pb.guard) == 2 &&
            !pa.seated && !pb.seated) {
          s = math.max(s, 0.7);
        }
        if (s > best || (s == best && s > 0 && d < bestD)) {
          best = s;
          bestD = d;
          pair = [
            math.min(pa.x1, pb.x1) / ar,
            math.min(pa.y1, pb.y1),
            math.max(pa.x2, pb.x2) / ar,
            math.max(pa.y2, pb.y2),
          ];
        }
      }
    }
    return (score: best, pair: pair);
  }
}
