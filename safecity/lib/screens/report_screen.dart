import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geocoding/geocoding.dart';
import 'my_reports_screen.dart';
import '../services/notification_service.dart';
import '../services/aive_service.dart';
import '../services/tflite_image_classifier.dart';
import '../services/cloudinary_service.dart';
import '../widgets/photo_check_indicator.dart';
import '../services/report_strike_service.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;
  final ImagePicker picker = ImagePicker();
  final TextEditingController descriptionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  static const int minDescLength = 20;
  static const int maxDescLength = 250;

  /// Real submit steps (the progress card shows which one is running).
  static const List<String> _loadingMessages = [
    "Getting your exact location",
    "Uploading photo",
    "AI verifying report",
    "Saving report",
  ];

  final List<Map<String, String>> categories = const [
    {"label": "Accident", "emoji": "🚗"},
    {"label": "Fire", "emoji": "🔥"},
    {"label": "Road Damage", "emoji": "🛣"},
    {"label": "Fight", "emoji": "👊"},
    {"label": "Harassment", "emoji": "👤"},
  ];

  File? image;
  DateTime? imageCapturedAt; // AIVE timestamp validation

  // Live AI photo check (runs right after capture / category change)
  ImageAnalysis? _photoAnalysis;
  String? _photoAnalysisCategory;
  bool _photoChecking = false;
  int _photoCheckRun = 0;

  // False-report strikes / restriction (ReportStrikeService)
  ReporterStanding? _standing;
  bool loading = false;
  Position? currentPosition;
  String selectedCategory = "Accident";

  String? currentAddress;
  bool loadingAddress = false;

  int descLength = 0;

  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  Timer? _loadingMessageTimer;
  int _loadingMessageIndex = 0;

  @override
  void initState() {
    super.initState();

    getCurrentLocation();
    _loadStanding();

    descriptionController.addListener(() {
      setState(() {
        descLength = descriptionController.text.length;
      });
    });

    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    descriptionController.dispose();
    _clockTimer?.cancel();
    _loadingMessageTimer?.cancel();
    super.dispose();
  }

  // ===============================
  // Location + reverse geocoding
  // ===============================
  Future<void> getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) return;
      if (permission == LocationPermission.deniedForever) return;

      currentPosition = await Geolocator.getCurrentPosition();

      if (mounted) setState(() {});

      await _reverseGeocode();
    } catch (e) {
      debugPrint("getCurrentLocation error: $e");
    }
  }

  Future<void> _reverseGeocode() async {
    if (currentPosition == null) return;

    setState(() => loadingAddress = true);

    try {
      final placemarks = await placemarkFromCoordinates(
        currentPosition!.latitude,
        currentPosition!.longitude,
      );

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [
          p.name,
          p.subLocality,
          p.locality,
        ].where((e) => e != null && e.trim().isNotEmpty).toSet().toList();
        currentAddress = parts.isNotEmpty ? parts.join(", ") : null;
      }
    } catch (e) {
      debugPrint("reverse geocode error: $e");
      currentAddress = null;
    } finally {
      if (mounted) setState(() => loadingAddress = false);
    }
  }

  // ===============================
  // Photo capture with size validation
  // ===============================
  Future<void> pickCamera() async {
    final XFile? file = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );

    if (file == null) return;

    final selected = File(file.path);
    final sizeInBytes = await selected.length();
    const maxSizeBytes = 5 * 1024 * 1024;

    if (sizeInBytes > maxSizeBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Image too large. Max size is 5 MB.")),
      );
      return;
    }

    setState(() {
      image = selected;
      imageCapturedAt = DateTime.now();
    });
    _runPhotoCheck();
  }

  void removeImage() {
    setState(() {
      image = null;
      imageCapturedAt = null;
      _resetPhotoCheck();
    });
  }

  Future<void> _loadStanding() async {
    try {
      final s =
          await ReportStrikeService().standing(auth.currentUser?.uid);
      if (mounted) setState(() => _standing = s);
    } catch (e) {
      debugPrint("Standing check failed: $e");
    }
  }

  void _resetPhotoCheck() {
    _photoCheckRun++; // ignore any check still running
    _photoAnalysis = null;
    _photoAnalysisCategory = null;
    _photoChecking = false;
  }

  /// Runs the on-device image model on the captured photo for the selected
  /// category and shows the result under the photo (red -> yellow -> green).
  Future<void> _runPhotoCheck() async {
    final file = image;
    if (file == null) return;
    final run = ++_photoCheckRun;
    final category = selectedCategory;
    setState(() {
      _photoChecking = true;
      _photoAnalysis = null;
      _photoAnalysisCategory = null;
    });

    ImageAnalysis? result;
    try {
      final r = await Future.wait<dynamic>([
        const TfliteImageClassifier().analyze(category, file),
        // keep the animation visible for a moment even on fast phones
        Future.delayed(const Duration(milliseconds: 1200)),
      ]);
      result = r[0] as ImageAnalysis?;
    } catch (e) {
      debugPrint("Photo check failed: $e");
    }

    if (!mounted || run != _photoCheckRun) return; // outdated check
    setState(() {
      _photoChecking = false;
      _photoAnalysis = result;
      _photoAnalysisCategory = category;
    });
  }

  // ===============================
  // Sequential Report ID generator (RP-1001, RP-1002, ...)
  // ===============================
  Future<String> _generateReportId() async {
    final counterRef = firestore.collection("meta").doc("counters");

    return firestore.runTransaction<String>((transaction) async {
      final snapshot = await transaction.get(counterRef);

      int current = 1000;
      if (snapshot.exists) {
        final data = snapshot.data();
        if (data != null && data.containsKey("reportCount")) {
          current = data["reportCount"] as int;
        }
      }

      final next = current + 1;

      transaction.set(counterRef, {
        "reportCount": next,
      }, SetOptions(merge: true));

      return "RP-$next";
    });
  }

  // ===============================
  // submitReport()
  // ===============================
  Future<void> submitReport() async {
    if (_standing?.isRestricted == true) {
      _showStrikeDetails();
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Current location not found.")),
      );
      return;
    }

    // AIVE needs a live photo to verify the incident.
    if (image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please capture a live photo of the incident.")),
      );
      return;
    }

    setState(() {
      loading = true;
      _loadingMessageIndex = 0;
    });

    _loadingMessageTimer?.cancel();
    void step(int i) {
      if (mounted) setState(() => _loadingMessageIndex = i);
    }

    final messenger = ScaffoldMessenger.of(context);

    try {
      final reportId = await _generateReportId();

      // ---- Refresh GPS fix right before submit (AIVE timestamp check) ----
      try {
        currentPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        // keep the earlier fix; AIVE will score its age
      }

      // ---- Upload captured photo to Cloudinary (free storage) ----
      step(1);
      String imageUrl = "";
      if (image != null) {
        try {
          imageUrl =
              await CloudinaryService.uploadReportImage(image!, reportId);
        } catch (e) {
          debugPrint("Image upload failed: $e");
        }
      }

      // ---- AIVE: automatic verification (no admin) ----
      step(2);
      // If AIVE fails for any reason the report is still saved exactly
      // like before (status "Pending") — submission never breaks.
      AiveResult aive;
      try {
        aive = await AiveService(classifier: const TfliteImageClassifier())
            .verify(
              category: selectedCategory,
              position: currentPosition!,
              userId: auth.currentUser?.uid,
              description: descriptionController.text.trim(),
              image: image,
              imageCapturedAt: imageCapturedAt,
              imageAnalysis: _photoAnalysisCategory == selectedCategory
                  ? _photoAnalysis
                  : null,
            )
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        debugPrint("AIVE failed: $e");
        aive = const AiveResult(
          status: "Pending",
          confidence: 0.5,
          imageScore: 0,
          gpsScore: 0,
          timeScore: 0,
          nearbyScore: 0,
          flags: ["AI verification unavailable — saved as Pending"],
        );
      }

      step(3);
      await firestore.collection("reports").add({
        "reportId": reportId,
        "category": selectedCategory,
        "description": descriptionController.text.trim(),
        "latitude": currentPosition!.latitude,
        "longitude": currentPosition!.longitude,
        "address": currentAddress ?? "",
        "gpsAccuracy": currentPosition!.accuracy,
        "imageUrl": imageUrl,
        "imageCapturedAt": imageCapturedAt != null
            ? Timestamp.fromDate(imageCapturedAt!)
            : null,
        "status": aive.status,
        "confidence": aive.confidence,
        "aive": aive.toMap(),
        "createdAt": FieldValue.serverTimestamp(),
        "userId": auth.currentUser?.uid,
        // false-report strike (proof = this report's photo + AIVE flags)
        "strike": ReportStrikeService.strikeFromFlags(aive.flags),
      });

      final locationPhrase =
          (currentAddress != null && currentAddress!.isNotEmpty)
          ? " near $currentAddress"
          : "";

      // UC-10 BR-1: only verified reports notify nearby users.
      if (aive.isPublic) {
        await NotificationService().createNotification(
          title: "$selectedCategory Reported",
          message:
              "A ${selectedCategory.toLowerCase()} has been reported$locationPhrase.",
          category: selectedCategory,
          latitude: currentPosition!.latitude,
          longitude: currentPosition!.longitude,
          userId: auth.currentUser?.uid,
        );
      }

      descriptionController.clear();
      image = null;
      imageCapturedAt = null;
      _resetPhotoCheck();
      setState(() {});

      if (!context.mounted) return;

      await _loadStanding(); // a new strike may restrict the account
      if (!context.mounted) return;
      await _showSuccessDialog(reportId, aive);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      _loadingMessageTimer?.cancel();
      if (context.mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> _showSuccessDialog(String reportId, AiveResult aive) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("✅", style: TextStyle(fontSize: 40)),
              SizedBox(height: 8),
              Text(
                "Report Submitted",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                aive.isPublic
                    ? "Thank you. Your report has been received.\n\nNearby users will be notified."
                    : "Your report has been received but was flagged by AI verification and will not be shown publicly.",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                "AI Verification: ${aive.status == AiveStatus.suspicious ? "Rejected" : aive.status} "
                "(${(aive.confidence * 100).round()}/100 points)",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: aive.status == AiveStatus.verified
                      ? Colors.green
                      : aive.status == AiveStatus.suspicious
                          ? Colors.red
                          : Colors.grey,
                ),
              ),
              if (ReportStrikeService.strikeFromFlags(aive.flags) != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    "⚠ False-report warning "
                    "${_standing?.count ?? 1}/${ReportStrikeService.restrictAt}: "
                    "${StrikeReason.label(ReportStrikeService.strikeFromFlags(aive.flags)!)}"
                    "${_standing?.isRestricted == true ? "\nReporting is now restricted." : ""}",
                    style: TextStyle(
                        color: Colors.red.shade800,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              if (aive.checks.isNotEmpty) ...[
                const SizedBox(height: 10),
                if (!aive.isVerified)
                  Text(
                    "Rejected because: "
                    "${aive.failedChecks.map((c) => c.name).join(", ")}",
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 6),
                // Every check with pass / fail and the reason
                for (final c in aive.checks)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          c.passed ? Icons.check_circle : Icons.cancel,
                          size: 16,
                          color: c.passed ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "${c.title}: ${c.detail}",
                            style: TextStyle(
                                fontSize: 12,
                                color: c.passed
                                    ? Colors.black54
                                    : Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
              ] else if (aive.flags.isNotEmpty) ...[
                const SizedBox(height: 6),
                ...aive.flags.map(
                  (f) => Text(
                    "• $f",
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "Report ID: #$reportId",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyReportsScreen()),
                );
              },
              child: const Text("View Reports"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Done"),
            ),
          ],
        );
      },
    );
  }

  // ===============================
  // Progress helpers
  // ===============================
  int get _completedSteps {
    int count = 0;
    if (currentPosition != null) count++;
    count++; // category always has a default selection
    if (image != null) count++;
    return count;
  }

  // ===============================
  // UI sections
  // ===============================
  Widget _buildHeroHeader() {
    const months = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December",
    ];
    final dateText = "${_now.day} ${months[_now.month - 1]} ${_now.year}";
    final timeText =
        "${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}";

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        24,
        MediaQuery.of(context).padding.top + 16,
        24,
        24,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff071B52), Color(0xff123a8f)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (Navigator.of(context).canPop())
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(height: 10),
          Row(
            children: const [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orangeAccent,
                size: 34,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Report an Incident",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "Help keep your city safe by reporting verified incidents.",
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 18),
          const Divider(color: Colors.white24),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.access_time,
                    color: Colors.white70,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(timeText, style: const TextStyle(color: Colors.white70)),
                ],
              ),
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    color: Colors.white70,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(dateText, style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection() {
    const total = 4;
    final done = _completedSteps;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "STEP $done of $total",
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: done / total,
              minHeight: 8,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Color(0xff66BB6A)),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _stepChip("Location", currentPosition != null),
              _stepChip("Category", true),
              _stepChip("Photo", image != null),
              _stepChip("Submit", false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepChip(String label, bool done) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 15,
          color: done ? Colors.greenAccent : Colors.white38,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 17,
        ),
      ),
    );
  }

  Widget _buildCategoryCards() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2.6,
      ),
      itemBuilder: (context, index) {
        final cat = categories[index];
        final selected = selectedCategory == cat["label"];

        return GestureDetector(
          onTap: () {
            if (selectedCategory == cat["label"]) return;
            setState(() {
              selectedCategory = cat["label"]!;
            });
            // the photo check depends on the category -> re-check
            if (image != null) _runPhotoCheck();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? const Color(0xff0A2E73) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? Colors.greenAccent : Colors.white24,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Text(cat["emoji"]!, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    cat["label"]!,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle,
                    color: Colors.greenAccent,
                    size: 18,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDescriptionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Describe the Incident",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: descriptionController,
            maxLines: 5,
            maxLength: maxDescLength,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Type details...",
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              counterText: "",
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return "Please enter incident description";
              }
              if (value.trim().length < minDescLength) {
                return "Description must be at least $minDescLength characters";
              }
              return null;
            },
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              "$descLength / $maxDescLength",
              style: TextStyle(
                color: descLength < minDescLength
                    ? Colors.orangeAccent
                    : Colors.white54,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accuracyBadge() {
    if (currentPosition == null) return const SizedBox();

    final accuracy = currentPosition!.accuracy;
    Color color;
    String label;

    if (accuracy <= 10) {
      color = Colors.green;
      label = "High Accuracy";
    } else if (accuracy <= 30) {
      color = Colors.orange;
      label = "Medium Accuracy";
    } else {
      color = Colors.red;
      label = "Low Accuracy";
    }

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          "${accuracy.toStringAsFixed(0)} m • $label",
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildLocationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: currentPosition == null
          ? const Row(
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(width: 15),
                Text(
                  "Getting current location...",
                  style: TextStyle(color: Colors.white),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.red),
                    const SizedBox(width: 8),
                    const Text(
                      "Current Location",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.verified,
                      color: Colors.greenAccent,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      "GPS Verified",
                      style: TextStyle(color: Colors.greenAccent, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (loadingAddress)
                  const Text(
                    "Finding address...",
                    style: TextStyle(color: Colors.white54),
                  )
                else
                  Text(
                    currentAddress ?? "Address not available",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Lat: ${currentPosition!.latitude.toStringAsFixed(4)}",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        "Lng: ${currentPosition!.longitude.toStringAsFixed(4)}",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _accuracyBadge(),
              ],
            ),
    );
  }

  Widget _buildPhotoCard() {
    if (image != null) {
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.file(
              image!,
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 12),
          PhotoCheckIndicator(
            checking: _photoChecking,
            verdict: _photoChecking
                ? null
                : AiveService.photoVerdict(selectedCategory, _photoAnalysis),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: pickCamera,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Retake"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: removeImage,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text("Remove"),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: pickCamera,
      child: Container(
        height: 220,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt, color: Colors.white70, size: 50),
            SizedBox(height: 12),
            Text(
              "Tap to Capture",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 6),
            Text(
              "PNG • JPG • JPEG",
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            Text(
              "Max 5 MB",
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafetyNotice() {
    final st = _standing;
    final restricted = st?.isRestricted == true;
    final warnings = st?.count ?? 0;
    final color = restricted ? Colors.redAccent : Colors.orangeAccent;

    String text;
    if (restricted) {
      final u = st!.restrictedUntil!;
      text = "Reporting restricted until ${u.day}/${u.month}/${u.year} - "
          "$warnings false-report warnings in the last 30 days. "
          "Tap to see the evidence.";
    } else if (warnings > 0) {
      text = "You have $warnings/${ReportStrikeService.restrictAt} "
          "false-report warnings (last 30 days). At "
          "${ReportStrikeService.restrictAt} reporting is blocked for 7 days. "
          "Tap to see details.";
    } else {
      text = "Submitting false information may result in account "
          "restrictions. Only report genuine incidents.";
    }

    return GestureDetector(
      onTap: warnings > 0 ? _showStrikeDetails : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(restricted ? Icons.block : Icons.warning_amber_rounded,
                color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(color: color, fontSize: 12.5)),
            ),
            if (warnings > 0) Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    );
  }

  /// Lists every strike with its proof (report ID, reason, AI evidence,
  /// photo) so the user can see exactly why they were warned / restricted.
  void _showStrikeDetails() {
    final st = _standing;
    if (st == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff0E2A6B),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              st.isRestricted
                  ? "Reporting restricted until "
                      "${st.restrictedUntil!.day}/${st.restrictedUntil!.month}/${st.restrictedUntil!.year}"
                  : "False-report warnings: ${st.count}/${ReportStrikeService.restrictAt}",
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              "Warnings are given only for clear evidence of a fake report: "
              "a photo of a screen, fake GPS, duplicate or spam reports. "
              "Warnings older than 30 days are removed automatically.",
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            for (final s in st.strikes)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (s.imageUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(s.imageUrl,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox(width: 64, height: 64)),
                      ),
                    if (s.imageUrl.isNotEmpty) const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("#${s.reportId} · ${s.category}",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          Text(
                              "${s.at.day}/${s.at.month}/${s.at.year} "
                              "${s.at.hour.toString().padLeft(2, '0')}:"
                              "${s.at.minute.toString().padLeft(2, '0')}",
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11)),
                          const SizedBox(height: 4),
                          Text(StrikeReason.label(s.reason),
                              style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5)),
                          for (final e in s.evidence)
                            Text("• $e",
                                style: const TextStyle(
                                    color: Colors.white60, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    if (loading) return _buildSubmitProgress();
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xff66BB6A),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        onPressed: _standing?.isRestricted == true ? null : submitReport,
        child: Text(
          _standing?.isRestricted == true
              ? "Reporting restricted"
              : "🚨 Submit Incident Report",
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  /// Shown while the report is being submitted: real step, progress bar
  /// and a checklist of the 4 steps.
  Widget _buildSubmitProgress() {
    final step = _loadingMessageIndex.clamp(0, _loadingMessages.length - 1);
    final total = _loadingMessages.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xff66BB6A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Submitting report · step ${step + 1} of $total",
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween(end: (step + 0.5) / total),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            builder: (_, v, __) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 10,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation(Color(0xff66BB6A)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < total; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: i < step
                        ? const Icon(Icons.check_circle,
                            color: Color(0xff66BB6A), size: 20)
                        : i == step
                            ? const Padding(
                                padding: EdgeInsets.all(2),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: Colors.white),
                              )
                            : const Icon(Icons.radio_button_unchecked,
                                color: Colors.white38, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _loadingMessages[i],
                    style: TextStyle(
                      color: i <= step ? Colors.white : Colors.white54,
                      fontWeight: i == step ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }


  Widget _buildTips() {
    const tips = [
      "Stay Safe",
      "Don't block traffic",
      "Capture clear image",
      "Avoid duplicate reports",
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Tips",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          ...tips.map(
            (tip) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Colors.greenAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(tip, style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===============================
  // BUILD
  // ===============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff071B52),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeroHeader(),
              _buildProgressSection(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle("Incident Category"),
                    _buildCategoryCards(),
                    const SizedBox(height: 25),
                    _buildDescriptionCard(),
                    const SizedBox(height: 25),
                    _sectionTitle("Current Location"),
                    _buildLocationCard(),
                    const SizedBox(height: 25),
                    _sectionTitle("Incident Photo"),
                    _buildPhotoCard(),
                    const SizedBox(height: 25),
                    _buildSafetyNotice(),
                    const SizedBox(height: 20),
                    _buildSubmitButton(),
                    const SizedBox(height: 25),
                    _buildTips(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
