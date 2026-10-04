// SafeCity - AI Test Lab
// =======================
// Lets the team / committee test the on-device AI WITHOUT submitting a
// report: capture a live photo with the camera, choose a category and see
// the photo check result (green / red ring) plus every model output.
// Camera only (no gallery), same as real reports. Nothing is uploaded.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/aive_service.dart';
import '../services/tflite_image_classifier.dart';
import '../widgets/photo_check_indicator.dart';

class AiTestLabScreen extends StatefulWidget {
  const AiTestLabScreen({super.key});

  @override
  State<AiTestLabScreen> createState() => _AiTestLabScreenState();
}

class _AiTestLabScreenState extends State<AiTestLabScreen> {
  static const _bg = Color(0xff071B52);
  static const _card = Color(0xff0E2A6B);
  static const _categories = [
    "Accident",
    "Fire",
    "Road Damage",
    "Fight",
    "Harassment",
  ];

  final _picker = ImagePicker();
  File? _image;
  String _category = "Accident";
  bool _checking = false;
  ImageAnalysis? _analysis;
  int _run = 0;

  Future<void> _capture() async {
    final f =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (f == null) return;
    setState(() => _image = File(f.path));
    _check();
  }

  Future<void> _check() async {
    final file = _image;
    if (file == null) return;
    final run = ++_run;
    final category = _category;
    setState(() {
      _checking = true;
      _analysis = null;
    });
    ImageAnalysis? a;
    try {
      final r = await Future.wait<dynamic>([
        const TfliteImageClassifier().analyze(category, file),
        Future.delayed(const Duration(milliseconds: 1200)),
      ]);
      a = r[0] as ImageAnalysis?;
    } catch (e) {
      debugPrint("AI test failed: $e");
    }
    if (!mounted || run != _run) return;
    setState(() {
      _checking = false;
      _analysis = a;
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = _analysis;
    final probs = a?.probabilities.entries.toList() ?? [];
    probs.sort((x, y) => y.value.compareTo(x.value));

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text("AI Test Lab",
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Capture a live photo to test the AI. Nothing is uploaded or reported.",
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),

          // Category
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _categories)
                ChoiceChip(
                  label: Text(c),
                  selected: _category == c,
                  onSelected: (_) {
                    setState(() => _category = c);
                    _check();
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Photo
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: _image == null
                ? Container(
                    height: 200,
                    color: _card,
                    child: const Center(
                      child: Icon(Icons.image_search,
                          color: Colors.white38, size: 48),
                    ),
                  )
                : Image.file(_image!,
                    height: 220, width: double.infinity, fit: BoxFit.cover),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              onPressed: _capture,
              icon: const Icon(Icons.camera_alt),
              label: Text(_image == null ? "Capture photo" : "Retake photo"),
            ),
          ),
          const SizedBox(height: 14),

          if (_image != null)
            PhotoCheckIndicator(
              checking: _checking,
              verdict: _checking
                  ? null
                  : AiveService.photoVerdict(_category, a),
            ),

          // All model outputs
          if (!_checking && probs.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: _card, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Model outputs",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  for (final e in probs)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 130,
                            child: Text(e.key,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: e.value,
                                minHeight: 8,
                                backgroundColor: Colors.white12,
                                valueColor: AlwaysStoppedAnimation(
                                    PhotoCheckIndicator.colorFor(e.value)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 44,
                            child: Text("${(e.value * 100).round()}%",
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  const Text(
                    "person = people visible (yes/no). screen = "
                    "photo taken of a laptop/phone screen. fight pose = two "
                    "people in a fighting pose (Fight only). normal = no incident.",
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
