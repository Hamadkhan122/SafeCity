// SafeCity - Emergency Live Chat screen
// Owner (person in danger) and their emergency contact chat in real time.
// The owner's live location is shown on the mini map and updated while the
// chat is open (if "Live location sharing" is ON in Settings).

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/phone_service.dart';
import '../services/settings_service.dart';
import '../services/sms_service.dart';
import '../services/sos_chat_service.dart';
import '../services/urgent_text.dart';
import 'map_screen.dart';

const _bg = Color(0xff071B52);
const _card = Color(0xff0E2A6B);

class SosChatScreen extends StatefulWidget {
  final String chatId;
  const SosChatScreen({super.key, required this.chatId});

  @override
  State<SosChatScreen> createState() => _SosChatScreenState();
}

class _SosChatScreenState extends State<SosChatScreen> {
  final _textC = TextEditingController();
  final _uid = FirebaseAuth.instance.currentUser?.uid;
  StreamSubscription<Position>? _posSub;
  GoogleMapController? _map;
  bool _sending = false;
  bool _isOwner = false;
  bool _ownerChecked = false;
  int _lang = 0; // quick replies: 0 English, 1 Roman Urdu, 2 Urdu
  Map<String, dynamic> _chat = {}; // latest chat doc (contact phone etc.)

  @override
  void dispose() {
    _posSub?.cancel();
    _textC.dispose();
    super.dispose();
  }

  void _startLiveLocation() {
    if (_posSub != null || !AppSettings.liveLocationSharing.value) return;
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen(
      (p) => SosChatService.updateLocation(widget.chatId, p.latitude, p.longitude)
          .catchError((_) {}),
      onError: (_) {},
    );
  }

  Future<void> _send(String text, {String type = "text"}) async {
    final t = text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      // Messages from the person in danger are checked for urgent words
      // (English / Roman Urdu / Urdu) and highlighted for the contact.
      final urgent = type == "text" && _isOwner && UrgentText.isUrgent(t);
      await SosChatService.sendMessage(widget.chatId,
          text: t, type: type, urgent: urgent);
      _textC.clear();
      if (type == "text") await _forwardBySms(t, urgent: urgent);
    } catch (e) {
      _snack("Message not sent: $e");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendLocation() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      await SosChatService.sendMessage(
        widget.chatId,
        text: "📍 My current location",
        type: "location",
        latitude: p.latitude,
        longitude: p.longitude,
      );
      if (_isOwner) {
        await SosChatService.updateLocation(
            widget.chatId, p.latitude, p.longitude);
      }
      await _forwardBySms(
          "My current location: ${SmsService.mapsLink(p.latitude, p.longitude)}");
    } catch (e) {
      _snack("Could not get location");
    }
  }

  Future<void> _endSos() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("End SOS?"),
        content: const Text(
            "Your contact will be told you are safe and live location sharing stops."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text("I'm safe")),
        ],
      ),
    );
    if (ok != true) return;
    _posSub?.cancel();
    _posSub = null;
    await SosChatService.endChat(widget.chatId);
    // Tell the contact by SMS too (they may not have the app).
    try {
      final c = await SosChatService.chats.doc(widget.chatId).get();
      final d = c.data() ?? {};
      await SmsService.sendSafe(
        (d["contactPhone"] ?? "").toString(),
        (d["ownerName"] ?? "Your contact").toString(),
      );
    } catch (_) {
      SmsService.stopLocationUpdates();
    }
    if (mounted) Navigator.pop(context);
  }

  /// If the emergency contact is NOT on SafeCity, the person in danger's
  /// chat messages are also sent to them by SMS, so they can read exactly
  /// what was typed (any language).
  Future<void> _forwardBySms(String text, {bool urgent = false}) async {
    if (!_isOwner || _chat["contactUid"] != null) return;
    final phone = (_chat["contactPhone"] ?? "").toString();
    if (phone.trim().isEmpty) return;
    final name = (_chat["ownerName"] ?? "SafeCity user").toString();
    final ok = await SmsService.send(
        phone, "${urgent ? "URGENT - " : ""}$name (SafeCity SOS): $text");
    if (ok) _snack("Also sent by SMS to ${_chat["contactName"] ?? phone}");
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _openOnMap(double lat, double lng, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          focusLat: lat,
          focusLng: lng,
          focusTitle: title,
          focusSnippet: "Shared in emergency chat",
        ),
      ),
    );
  }

  String _ago(dynamic ts) {
    if (ts is! Timestamp) return "just now";
    final d = DateTime.now().difference(ts.toDate());
    if (d.inSeconds < 60) return "just now";
    if (d.inMinutes < 60) return "${d.inMinutes} min ago";
    return "${d.inHours} h ago";
  }

  String _time(dynamic ts) {
    if (ts is! Timestamp) return "";
    final t = ts.toDate();
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return "$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? "AM" : "PM"}";
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: SosChatService.chat(widget.chatId),
      builder: (context, snap) {
        final c = snap.data?.data() ?? {};
        if (c.isNotEmpty) _chat = c;
        final active = c["active"] == true;
        final isOwner = c["ownerId"] == _uid;

        if (snap.hasData && !_ownerChecked) {
          _ownerChecked = true;
          _isOwner = isOwner;
          if (isOwner && active) _startLiveLocation();
        }

        final otherName = isOwner
            ? (c["contactName"] ?? "Emergency contact").toString()
            : (c["ownerName"] ?? "SafeCity user").toString();
        final otherPhone = isOwner
            ? (c["contactPhone"] ?? "").toString()
            : (c["ownerPhone"] ?? "").toString();
        final lat = (c["latitude"] as num?)?.toDouble();
        final lng = (c["longitude"] as num?)?.toDouble();

        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            titleSpacing: 0,
            title: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      active ? const Color(0xffD32F2F) : Colors.white24,
                  child: const Icon(Icons.sos, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(otherName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      Text(
                        active ? "Emergency live chat" : "SOS ended",
                        style: TextStyle(
                            color: active ? Colors.redAccent : Colors.white54,
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              if (otherPhone.isNotEmpty)
                IconButton(
                  tooltip: "Call",
                  icon: const Icon(Icons.call, color: Colors.greenAccent),
                  onPressed: () =>
                      PhoneService.call(context, otherPhone, label: otherName),
                ),
              if (isOwner && active)
                TextButton(
                  onPressed: _endSos,
                  child: const Text("I'm safe",
                      style: TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          body: Column(
            children: [
              if (lat != null && lng != null) _locationCard(c, lat, lng),
              Expanded(child: _messageList()),
              if (active) _quickReplies(isOwner),
              if (active) _inputBar() else _endedBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _locationCard(Map<String, dynamic> c, double lat, double lng) {
    final target = LatLng(lat, lng);
    _map?.animateCamera(CameraUpdate.newLatLng(target));
    final owner = (c["ownerName"] ?? "User").toString();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 130,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: target, zoom: 15),
              markers: {
                Marker(
                  markerId: const MarkerId("owner"),
                  position: target,
                  infoWindow: InfoWindow(title: owner),
                ),
              },
              onMapCreated: (m) => _map = m,
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
              liteModeEnabled: false,
            ),
          ),
          ListTile(
            dense: true,
            leading: Icon(
              Icons.share_location,
              color: c["active"] == true ? Colors.greenAccent : Colors.white38,
            ),
            title: Text(
              c["active"] == true
                  ? "$owner's live location"
                  : "$owner's last location",
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text("Updated ${_ago(c["locationUpdatedAt"])}",
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            trailing: TextButton(
              onPressed: () => _openOnMap(lat, lng, owner),
              child: const Text("Directions"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: SosChatService.messages(widget.chatId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.white));
        }
        final docs = snap.data!.docs;
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: docs.length,
          itemBuilder: (_, i) => _bubble(docs[i].data()),
        );
      },
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final type = (m["type"] ?? "text").toString();
    final text = (m["text"] ?? "").toString();

    if (type == "system") {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
      );
    }

    final mine = m["senderId"] == _uid;
    final urgent = m["urgent"] == true;
    final rtl = UrgentText.isRtl(text);
    final lat = (m["latitude"] as num?)?.toDouble();
    final lng = (m["longitude"] as num?)?.toDouble();
    final color = type == "alert" || urgent
        ? const Color(0xffD32F2F)
        : mine
            ? const Color(0xff1E88E5)
            : _card;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: lat != null && lng != null
            ? () => _openOnMap(lat, lng, (m["senderName"] ?? "").toString())
            : null,
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                Text((m["senderName"] ?? "").toString(),
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              if (urgent)
                const Padding(
                  padding: EdgeInsets.only(bottom: 2),
                  child: Text("⚠ URGENT",
                      style: TextStyle(
                          color: Colors.yellowAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              Text(text,
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  style: const TextStyle(color: Colors.white)),
              if (urgent && !mine)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: InkWell(
                    onTap: () =>
                        PhoneService.call(context, "15", label: "Police 15"),
                    child: const Text("📞 Call Police 15",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline)),
                  ),
                ),
              if (lat != null && lng != null)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text("Tap to open on map",
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          decoration: TextDecoration.underline)),
                ),
              const SizedBox(height: 2),
              Text(_time(m["createdAt"]),
                  style: const TextStyle(color: Colors.white54, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickReplies(bool isOwner) {
    const ownerReplies = [
      ["Please call me", "Send help to my location", "I'm hiding, can't talk"],
      ["Mujhe call karo", "Meri location par madad bhejo", "Main chhup kar hun, baat nahi ho sakti"],
      ["مجھے کال کرو", "میری لوکیشن پر مدد بھیجو", "میں چھپ کر ہوں، بات نہیں ہو سکتی"],
    ];
    const contactReplies = [
      ["On my way", "Calling you now", "I've called 15 / 1122", "Stay where you are"],
      ["Hum aa rahe hain", "Abhi call kar rahe hain", "15 / 1122 ko call kar di", "Wahin rehna"],
      ["ہم آ رہے ہیں", "ابھی کال کر رہے ہیں", "15 / 1122 کو کال کر دی", "وہیں رہنا"],
    ];
    const langLabels = ["EN", "Roman", "اردو"];
    final replies = (isOwner ? ownerReplies : contactReplies)[_lang];
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 6),
            child: ActionChip(
              backgroundColor: const Color(0xff1E88E5),
              avatar: const Icon(Icons.translate, size: 16, color: Colors.white),
              label: Text(langLabels[_lang],
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              onPressed: () => setState(() => _lang = (_lang + 1) % 3),
            ),
          ),
          for (final r in replies)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 6),
              child: ActionChip(
                backgroundColor: _card,
                side: const BorderSide(color: Colors.white24),
                label: Text(r,
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
                onPressed: () => _send(r),
              ),
            ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: "Send my location",
              onPressed: _sendLocation,
              icon: const Icon(Icons.my_location, color: Colors.white),
            ),
            Expanded(
              child: TextField(
                controller: _textC,
                onChanged: (_) => setState(() {}),
                textDirection: UrgentText.isRtl(_textC.text)
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                decoration: InputDecoration(
                  hintText: "Type a message... (English / Roman Urdu / اردو)",
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: _card,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xffD32F2F),
              child: IconButton(
                onPressed: _sending ? null : () => _send(_textC.text),
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _endedBar() => SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          color: _card,
          child: const Text("This SOS has ended. Chat is read-only.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70)),
        ),
      );
}
