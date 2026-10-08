// SafeCity - SOS Emergency Screen (SRS 4.7: FR-SOS-01..03, SDD Function 9)
// =====================================================
// - Emergency contact saved in Firestore users/{uid}.emergency_contact
// - SOS: capture GPS -> store alert in "sos_alerts" -> SMS to contact with
//   live location -> confirmation dialog
// - Helplines (15 / 1122 / 16 / 115): one tap opens the phone dialer
// - Nearest Police / Hospital / Fire station (Google Places):
//     Call -> station number if Google has it, otherwise the matching
//             national helpline, opened in the phone dialer
//     Directions -> opens the place on the Live Map
//
// Dialer / SMS need the <queries> entries in AndroidManifest.xml (Android 11+).

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/places_service.dart';
import '../services/phone_service.dart';
import '../services/share_service.dart';
import '../services/sos_chat_service.dart';
import '../services/sms_service.dart';
import 'sos_chat_screen.dart';
import 'map_screen.dart';

const _bg = Color(0xff071B52);
const _card = Color(0xff0E2A6B);

class _Helpline {
  final String label;
  final String number;
  final IconData icon;
  final Color color;
  const _Helpline(this.label, this.number, this.icon, this.color);
}

const _helplines = [
  _Helpline("Police", "15", Icons.local_police, Color(0xff42A5F5)),
  _Helpline("Rescue", "1122", Icons.medical_services, Color(0xffEF5350)),
  _Helpline("Fire", "16", Icons.local_fire_department, Color(0xffFF7043)),
  _Helpline("Edhi", "115", Icons.airport_shuttle, Color(0xff66BB6A)),
];

class SosScreen extends StatefulWidget {
  /// true -> SOS is sent automatically as soon as the screen opens
  /// (used by Accident Detection when the user doesn't respond).
  final bool autoSend;
  final String? reason;
  const SosScreen({super.key, this.autoSend = false, this.reason});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen>
    with SingleTickerProviderStateMixin {
  final PlacesService placesService = PlacesService();

  String? emergencyContactName;
  String? emergencyContactPhone;
  bool isEditingContact = false;
  bool loadingContact = true;
  bool isSendingSOS = false;
  bool loadingPlaces = true;
  bool _autoSent = false;
  bool openingChat = false;
  bool smsAutoSent = false;
  String? activeChatId;

  Position? currentPosition;
  Map<String, dynamic>? nearestPolice;
  Map<String, dynamic>? nearestHospital;
  Map<String, dynamic>? nearestFire;

  // What is the emergency? (optional, shown in the SMS + chat)
  static const List<String> _emergencyTypes = [
    "Being followed / Harassment",
    "Accident",
    "Medical",
    "Fire",
    "Robbery / Threat",
    "Other",
  ];
  String? _emergencyType;
  final TextEditingController noteController = TextEditingController();

  /// "Accident - car hit my bike near Comsats gate" (or "I need help").
  String _reason() {
    final parts = <String>[
      if (widget.reason != null && widget.reason!.trim().isNotEmpty)
        widget.reason!.trim(),
      if (_emergencyType != null) _emergencyType!,
      if (noteController.text.trim().isNotEmpty) noteController.text.trim(),
    ];
    return parts.isEmpty ? "I need help" : parts.join(" - ");
  }

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _loadEmergencyContact();
    _loadPositionAndPlaces();
  }

  @override
  void dispose() {
    _pulse.dispose();
    nameController.dispose();
    noteController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------------------
  // Dialer / SMS helpers
  // ---------------------------------------------------------------
  // Direct call (returns to the app after the call), dialer as fallback.
  Future<void> _dial(String number, {String? label}) =>
      PhoneService.call(context, number, label: label);

  Future<bool> _openSms(String phone, String body) async {
    try {
      return await launchUrl(
        // encodeComponent (not queryParameters) so spaces don't become '+'
        Uri.parse('sms:$phone?body=${Uri.encodeComponent(body)}'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------
  // Emergency contact — Firestore users/{uid}.emergency_contact
  // ---------------------------------------------------------------
  Future<void> _loadEmergencyContact() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => loadingContact = false);
      return;
    }

    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final contact = doc.data()?['emergency_contact'];

      if (!mounted) return;
      if (contact != null) {
        setState(() {
          emergencyContactName = contact['name'];
          emergencyContactPhone = contact['phone'];
        });
      } else {
        setState(() => isEditingContact = true);
      }
    } catch (e) {
      debugPrint("Emergency contact load error: $e");
      if (mounted) setState(() => isEditingContact = true);
    } finally {
      if (mounted) setState(() => loadingContact = false);
      if (widget.autoSend && !_autoSent && mounted) {
        _autoSent = true;
        _sendSOS();
      }
    }
  }

  bool _isValidPhone(String phone) =>
      RegExp(r'^\+?[0-9\-\s]{7,15}$').hasMatch(phone.trim());

  Future<void> _saveEmergencyContact() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final name = nameController.text.trim();
    final phone = phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      _snack('Please enter both name and phone number');
      return;
    }
    if (!_isValidPhone(phone)) {
      _snack('Enter a valid phone number (e.g. 03001234567)');
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'emergency_contact': {'name': name, 'phone': phone},
      }, SetOptions(merge: true));

      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() {
        emergencyContactName = name;
        emergencyContactPhone = phone;
        isEditingContact = false;
      });
      _snack('Emergency contact saved');
    } catch (e) {
      _snack('Could not save contact: $e');
    }
  }

  // ---------------------------------------------------------------
  // Position + nearest places
  // ---------------------------------------------------------------
  Future<void> _loadPositionAndPlaces() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final lat = currentPosition!.latitude;
      final lng = currentPosition!.longitude;

      final results = await Future.wait([
        placesService.nearbyPlaces(latitude: lat, longitude: lng, type: "police"),
        placesService.nearbyPlaces(latitude: lat, longitude: lng, type: "hospital"),
        placesService.nearbyPlaces(
            latitude: lat, longitude: lng, type: "fire_station"),
      ]);
      nearestPolice = _nearest(results[0]);
      nearestHospital = _nearest(results[1]);
      nearestFire = _nearest(results[2]);
    } catch (e) {
      debugPrint("SOS load places error: $e");
    } finally {
      if (mounted) setState(() => loadingPlaces = false);
    }
  }

  Map<String, dynamic>? _nearest(List<dynamic> places) {
    if (currentPosition == null || places.isEmpty) return null;
    Map<String, dynamic>? nearest;
    double best = double.infinity;
    for (var place in places) {
      final d = _distanceTo(place);
      if (d < best) {
        best = d;
        nearest = place;
      }
    }
    return nearest;
  }

  double _distanceTo(Map<String, dynamic> place) {
    final lat = (place["geometry"]["location"]["lat"] as num).toDouble();
    final lng = (place["geometry"]["location"]["lng"] as num).toDouble();
    return Geolocator.distanceBetween(
      currentPosition!.latitude,
      currentPosition!.longitude,
      lat,
      lng,
    );
  }

  String _distanceText(Map<String, dynamic> place) {
    if (currentPosition == null) return "";
    final d = _distanceTo(place);
    return d < 1000
        ? "${d.toStringAsFixed(0)} m away"
        : "${(d / 1000).toStringAsFixed(1)} km away";
  }

  // Station number from Google if available, otherwise national helpline.
  Future<void> _callPlace(Map<String, dynamic>? place, _Helpline fallback) async {
    String? phone;
    if (place != null && place["place_id"] != null) {
      try {
        final details = await placesService.getPlaceDetails(place["place_id"]);
        phone = details?["formatted_phone_number"] ??
            details?["international_phone_number"];
      } catch (_) {}
    }
    if (phone == null || phone.toString().trim().isEmpty) {
      _snack("Station number not listed — calling ${fallback.label} "
          "helpline ${fallback.number}");
      await _dial(fallback.number, label: "${fallback.label} (${fallback.number})");
    } else {
      await _dial(phone.toString(), label: place?["name"]?.toString());
    }
  }

  void _openOnMap(Map<String, dynamic> place) {
    final lat = (place["geometry"]["location"]["lat"] as num).toDouble();
    final lng = (place["geometry"]["location"]["lng"] as num).toDouble();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          focusLat: lat,
          focusLng: lng,
          focusTitle: place["name"] ?? "Nearest location",
          focusSnippet: place["vicinity"] ?? "",
          routeToFocus: true, // show the route straight away
        ),
      ),
    );
  }

  // Share sheet (WhatsApp, SMS, Gmail...) with a Google Maps link.
  Future<void> _shareMyLocation() async {
    Position? p = currentPosition;
    try {
      p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {}
    if (p == null) {
      _snack("Could not get your location");
      return;
    }
    if (!mounted) return;
    await ShareService.shareText(
      context,
      ShareService.locationMessage(p.latitude, p.longitude),
      title: "Share your location via",
    );
  }

  // ---------------------------------------------------------------
  // SOS — SDD Function 9
  // ---------------------------------------------------------------
  Future<void> _sendSOS() async {
    if (emergencyContactPhone == null) {
      _snack('Please save an emergency contact first');
      setState(() => isEditingContact = true);
      return;
    }

    setState(() => isSendingSOS = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final mapsLink =
          'https://www.google.com/maps?q=${position.latitude},${position.longitude}';

      String? alertId;
      try {
        final ref = FirebaseFirestore.instance.collection('sos_alerts').doc();
        alertId = ref.id;
        await ref.set({
          'alertId': ref.id,
          'userId': FirebaseAuth.instance.currentUser?.uid,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'contactName': emergencyContactName,
          'contactPhone': emergencyContactPhone,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint("SOS alert store failed: $e");
      }

      // In-app emergency live chat with the contact.
      try {
        activeChatId = await SosChatService.startChat(
          latitude: position.latitude,
          longitude: position.longitude,
          contactName: emergencyContactName,
          contactPhone: emergencyContactPhone,
          alertId: alertId,
          reason: _reason(),
        );
      } catch (e) {
        debugPrint("SOS chat start failed: $e");
      }

      // 1) Try to send the SMS automatically (works even if the contact has
      //    no app / no internet). 2) Fall back to the messaging app.
      final myName = await _myName();
      smsAutoSent = await SmsService.send(
        emergencyContactPhone!,
        SmsService.sosText(myName, _reason(),
            position.latitude, position.longitude),
      );
      if (smsAutoSent && activeChatId != null) {
        SmsService.startLocationUpdates(
          chatId: activeChatId!,
          phone: emergencyContactPhone!,
          name: myName,
        );
      }

      final opened = smsAutoSent ||
          await _openSms(
            emergencyContactPhone!,
            "EMERGENCY! ${_reason()}. "
            "My live location: $mapsLink\n"
            "Chat with me in the SafeCity app.",
          );

      if (!mounted) return;
      if (!smsAutoSent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 8),
          content: const Text(
              "Automatic SMS needs the SMS permission. Allow it in Settings "
              "so next time SOS is sent without pressing Send."),
          action: SnackBarAction(
              label: "Settings", onPressed: () => openAppSettings()),
        ));
      }
      if (opened) {
        _showConfirmation(alertId);
      } else {
        _snack('Could not open messaging app');
        if (activeChatId != null) _goToChat(activeChatId!);
      }
    } catch (e) {
      _snack('Could not get your location: $e');
    } finally {
      if (mounted) setState(() => isSendingSOS = false);
    }
  }

  void _showConfirmation(String? alertId) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 48),
            SizedBox(height: 8),
            Text("SOS Alert Created",
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          smsAutoSent
              ? "SMS with your live location was sent automatically to "
                  "$emergencyContactName ($emergencyContactPhone).\n\n"
                  "Location updates will be sent by SMS every 5 minutes "
                  "until you tap \"I'm safe\" in the live chat."
              : "Your location has been recorded and a message to "
                  "$emergencyContactName ($emergencyContactPhone) is ready.\n\n"
                  "Make sure you tapped Send in your messaging app.",
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _dial(emergencyContactPhone!, label: emergencyContactName);
            },
            child: const Text("Call contact"),
          ),
          if (activeChatId != null)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _goToChat(activeChatId!);
              },
              child: const Text("Open live chat"),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<String> _myName() async {
    final u = FirebaseAuth.instance.currentUser;
    try {
      final d = await FirebaseFirestore.instance
          .collection('users')
          .doc(u?.uid)
          .get();
      final n = (d.data()?['fullName'] ?? '').toString().trim();
      if (n.isNotEmpty) return n;
    } catch (_) {}
    return u?.email ?? 'A SafeCity user';
  }

  // ---------------------------------------------------------------
  // Emergency live chat (in-app)
  // ---------------------------------------------------------------
  void _goToChat(String chatId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SosChatScreen(chatId: chatId)),
    );
  }

  Future<void> _openLiveChat() async {
    if (emergencyContactPhone == null) {
      _snack('Please save an emergency contact first');
      setState(() => isEditingContact = true);
      return;
    }
    setState(() => openingChat = true);
    try {
      String? id = activeChatId ?? await SosChatService.activeChatId();
      if (id == null) {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
        id = await SosChatService.startChat(
          latitude: p.latitude,
          longitude: p.longitude,
          contactName: emergencyContactName,
          contactPhone: emergencyContactPhone,
          reason: "Emergency chat",
        );
      }
      activeChatId = id;
      if (mounted) _goToChat(id);
    } catch (e) {
      _snack('Could not start chat: $e');
    } finally {
      if (mounted) setState(() => openingChat = false);
    }
  }

  Widget _liveChatCard() {
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: openingChat ? null : _openLiveChat,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x66EF5350)),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 22,
                backgroundColor: Color(0x33EF5350),
                child: Icon(Icons.forum, color: Color(0xffEF5350)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Emergency Live Chat",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    SizedBox(height: 2),
                    Text(
                      "Chat with your emergency contact inside the app "
                      "and share live location",
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              openingChat
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.chevron_right, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "Emergency SOS",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _contactCard(),
            const SizedBox(height: 18),
            _emergencyPicker(),
            const SizedBox(height: 22),
            _sosButton(),
            const SizedBox(height: 14),
            const Text(
              "Tap SOS to send an SMS with your live location to your "
              "emergency contact.\nChoosing the emergency type is optional.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),
            Center(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: _shareMyLocation,
                icon: const Icon(Icons.share_location),
                label: const Text("Share my location"),
              ),
            ),
            const SizedBox(height: 18),
            _liveChatCard(),
            const SizedBox(height: 24),
            _sectionTitle("Emergency Helplines"),
            const SizedBox(height: 10),
            _helplineGrid(),
            const SizedBox(height: 24),
            _sectionTitle("Nearest Help"),
            const SizedBox(height: 10),
            if (loadingPlaces)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator(color: Colors.white)),
              )
            else ...[
              _placeTile("Police Station", Icons.local_police, nearestPolice,
                  _helplines[0]),
              _placeTile("Hospital", Icons.local_hospital, nearestHospital,
                  _helplines[1]),
              _placeTile("Fire Station", Icons.local_fire_department,
                  nearestFire, _helplines[2]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emergencyPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("What is the emergency? (optional)",
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in _emergencyTypes)
              ChoiceChip(
                label: Text(t, style: const TextStyle(fontSize: 12)),
                selected: _emergencyType == t,
                selectedColor: const Color(0xffEF5350),
                backgroundColor: _card,
                labelStyle: TextStyle(
                    color: _emergencyType == t ? Colors.white : Colors.white70),
                side: const BorderSide(color: Colors.white24),
                onSelected: (sel) =>
                    setState(() => _emergencyType = sel ? t : null),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: noteController,
          maxLength: 100,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Short note, e.g. Comsats gate par hun, koi peecha kar raha hai",
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
            counterStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: _card,
            prefixIcon: const Icon(Icons.edit_note, color: Colors.white54),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      );

  Widget _contactCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: loadingContact
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          : isEditingContact
              ? _contactForm()
              : Row(
                  children: [
                    const CircleAvatar(
                      radius: 22,
                      backgroundColor: Color(0x33FFFFFF),
                      child: Icon(Icons.contact_phone, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Emergency Contact",
                              style: TextStyle(color: Colors.white54, fontSize: 11)),
                          const SizedBox(height: 2),
                          Text(
                            emergencyContactName ?? "",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(emergencyContactPhone ?? "",
                              style: const TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: "Call",
                      onPressed: () => _dial(emergencyContactPhone!,
                          label: emergencyContactName),
                      icon: const Icon(Icons.call, color: Colors.greenAccent),
                    ),
                    IconButton(
                      tooltip: "Change contact",
                      onPressed: () {
                        nameController.text = emergencyContactName ?? '';
                        phoneController.text = emergencyContactPhone ?? '';
                        setState(() => isEditingContact = true);
                      },
                      icon: const Icon(Icons.edit, color: Colors.white70),
                    ),
                  ],
                ),
    );
  }

  Widget _contactForm() {
    InputDecoration deco(String label, IconData icon, [String? hint]) =>
        InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.white70),
          labelStyle: const TextStyle(color: Colors.white70),
          hintStyle: const TextStyle(color: Colors.white38),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "Add Emergency Contact",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: deco("Contact name", Icons.person),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: Colors.white),
          decoration: deco("Phone number", Icons.phone, "03001234567"),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (emergencyContactPhone != null)
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    setState(() => isEditingContact = false);
                  },
                  child: const Text("Cancel"),
                ),
              ),
            if (emergencyContactPhone != null) const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _saveEmergencyContact,
                child: const Text("Save Contact"),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sosButton() {
    return Center(
      child: SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) {
                final t = _pulse.value;
                return Container(
                  width: 140 + 60 * t,
                  height: 140 + 60 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red.withValues(alpha: 0.35 * (1 - t)),
                  ),
                );
              },
            ),
            GestureDetector(
              onTap: isSendingSOS ? null : _sendSOS,
              child: Container(
                width: 140,
                height: 140,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0xffFF5252), Color(0xffC62828)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x88FF1744),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: isSendingSOS
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "SOS",
                            style: TextStyle(
                              fontSize: 40,
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                          Text(
                            "TAP FOR HELP",
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white70,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _helplineGrid() {
    return Row(
      children: [
        for (int i = 0; i < _helplines.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _helplineButton(_helplines[i])),
        ],
      ],
    );
  }

  Widget _helplineButton(_Helpline h) {
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _dial(h.number, label: "${h.label} helpline"),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: h.color.withValues(alpha: 0.2),
                child: Icon(h.icon, color: h.color),
              ),
              const SizedBox(height: 8),
              Text(h.label,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              Text(
                h.number,
                style: TextStyle(
                  color: h.color,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeTile(
    String type,
    IconData icon,
    Map<String, dynamic>? place,
    _Helpline fallback,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: fallback.color.withValues(alpha: 0.2),
            child: Icon(icon, color: fallback.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type,
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
                Text(
                  place?["name"] ?? "None found nearby",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  place != null
                      ? _distanceText(place)
                      : "Call helpline ${fallback.number}",
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: "Call",
            onPressed: () => _callPlace(place, fallback),
            icon: const Icon(Icons.call, color: Colors.greenAccent),
          ),
          if (place != null)
            IconButton(
              tooltip: "Directions",
              onPressed: () => _openOnMap(place),
              icon: const Icon(Icons.directions, color: Colors.lightBlueAccent),
            ),
        ],
      ),
    );
  }
}
