import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geocoding/geocoding.dart';
import 'my_reports_screen.dart';
import '../services/notification_service.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseStorage storage = FirebaseStorage.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;
  final ImagePicker picker = ImagePicker();
  final TextEditingController descriptionController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  static const int minDescLength = 20;
  static const int maxDescLength = 250;

  static const List<String> _loadingMessages = [
    "Uploading...",
    "Saving Report...",
    "Please Wait...",
  ];

  final List<Map<String, String>> categories = const [
    {"label": "Accident", "emoji": "🚗"},
    {"label": "Fire", "emoji": "🔥"},
    {"label": "Theft", "emoji": "⚠️"},
    {"label": "Road Damage", "emoji": "🛣"},
    {"label": "Fight", "emoji": "👊"},
    {"label": "Harassment", "emoji": "👤"},
  ];

  File? image;
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
    });
  }

  void removeImage() {
    setState(() => image = null);
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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Current location not found.")),
      );
      return;
    }

    setState(() {
      loading = true;
      _loadingMessageIndex = 0;
    });

    _loadingMessageTimer?.cancel();
    _loadingMessageTimer = Timer.periodic(const Duration(milliseconds: 1200), (
      _,
    ) {
      if (!mounted) return;
      setState(() {
        _loadingMessageIndex =
            (_loadingMessageIndex + 1) % _loadingMessages.length;
      });
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      final reportId = await _generateReportId();

      String imageUrl = "";
      // Image upload abhi skip — Firebase Storage baad me add karenge

      await firestore.collection("reports").add({
        "reportId": reportId,
        "category": selectedCategory,
        "description": descriptionController.text.trim(),
        "latitude": currentPosition!.latitude,
        "longitude": currentPosition!.longitude,
        "address": currentAddress ?? "",
        "gpsAccuracy": currentPosition!.accuracy,
        "imageUrl": imageUrl,
        "status": "Pending",
        "createdAt": FieldValue.serverTimestamp(),
        "userId": auth.currentUser?.uid,
      });

      final locationPhrase =
          (currentAddress != null && currentAddress!.isNotEmpty)
          ? " near $currentAddress"
          : "";

      await NotificationService().createNotification(
        title: "$selectedCategory Reported",
        message:
            "A ${selectedCategory.toLowerCase()} has been reported$locationPhrase.",
        category: selectedCategory,
        latitude: currentPosition!.latitude,
        longitude: currentPosition!.longitude,
      );

      descriptionController.clear();
      image = null;
      setState(() {});

      if (!context.mounted) return;

      await _showSuccessDialog(reportId);
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

  Future<void> _showSuccessDialog(String reportId) {
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Thank you. Your report has been received.\n\nNearby users will be notified.",
                textAlign: TextAlign.center,
              ),
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
            setState(() {
              selectedCategory = cat["label"]!;
            });
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Submitting false information may result in account restrictions. Only report genuine incidents.",
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
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
        onPressed: loading ? null : submitReport,
        child: loading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    _loadingMessages[_loadingMessageIndex],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            : const Text(
                "🚨 Submit Incident Report",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
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
