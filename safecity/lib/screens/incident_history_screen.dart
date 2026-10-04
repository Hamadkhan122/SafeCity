// SafeCity - Incident History (community report history)
// =====================================================
// - All community reports (newest first), live from Firestore "reports"
// - Filters: category, status (All / Verified / Rejected), date
//   (All time / Today / This week / This month)
// - Search by area, description or category
// - Summary: reports in the current filter + most reported category
// - Tap a report -> IncidentDetailScreen (photo, map, AIVE confidence)
//
// Privacy: AIVE-rejected (Suspicious/Rejected) reports are NOT public.
// A user only sees their OWN rejected reports (under the "Rejected" filter).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/safety_score_service.dart';
import 'map_screen.dart';
import 'my_reports_screen.dart';

const _bg = Color(0xff071B52);
const _card = Color(0xff0E2A6B);
const _green = Color(0xff66BB6A);

bool _isVerified(String s) => s == "Verified" || s == "Partially Verified";
bool _isRejected(String s) => s == "Suspicious" || s == "Rejected";
String _statusLabel(String s) => s == "Suspicious" ? "Rejected" : s;

class IncidentHistoryScreen extends StatefulWidget {
  const IncidentHistoryScreen({super.key});

  @override
  State<IncidentHistoryScreen> createState() => _IncidentHistoryScreenState();
}

class _IncidentHistoryScreenState extends State<IncidentHistoryScreen> {
  static const _categories = [
    "All",
    "Accident",
    "Fire",
    "Harassment",
    "Road Damage",
    "Fight",
  ];
  static const _statuses = ["All", "Verified", "Rejected"];
  static const _dates = ["All time", "Today", "This week", "This month"];

  final _uid = FirebaseAuth.instance.currentUser?.uid;
  final _searchC = TextEditingController();
  String _category = "All";
  String _status = "All";
  String _date = "All time";
  String _query = "";
  Position? _me;

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  Future<void> _loadPosition() async {
    try {
      final p = await Geolocator.getLastKnownPosition();
      if (mounted && p != null) setState(() => _me = p);
    } catch (_) {}
  }

  bool _matches(Map<String, dynamic> d) {
    final status = (d["status"] ?? "Pending").toString();
    final category = (d["category"] ?? "").toString();
    if (!SafetyScoreService.isSupportedCategory(category)) return false;

    // Status + privacy
    if (_isRejected(status)) {
      if (_status != "Rejected" || d["userId"] != _uid) return false;
    } else {
      if (_status == "Rejected") return false;
      if (_status == "Verified" && !_isVerified(status)) return false;
    }

    if (_category != "All" && category != _category) return false;

    // Date
    if (_date != "All time") {
      final ts = d["createdAt"];
      if (ts is! Timestamp) return false;
      final t = ts.toDate();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final from = _date == "Today"
          ? today
          : _date == "This week"
              ? today.subtract(Duration(days: today.weekday - 1))
              : DateTime(now.year, now.month, 1);
      if (t.isBefore(from)) return false;
    }

    // Search
    if (_query.isNotEmpty) {
      final text = "${d["address"] ?? ""} ${d["description"] ?? ""} $category"
          .toLowerCase();
      for (final word in _query.toLowerCase().split(RegExp(r"\s+"))) {
        if (word.isNotEmpty && !text.contains(word)) return false;
      }
    }
    return true;
  }

  String _distance(Map<String, dynamic> d) {
    if (_me == null || d["latitude"] == null || d["longitude"] == null) {
      return "";
    }
    final m = Geolocator.distanceBetween(_me!.latitude, _me!.longitude,
        (d["latitude"] as num).toDouble(), (d["longitude"] as num).toDouble());
    return m < 1000
        ? "${m.toStringAsFixed(0)} m away"
        : "${(m / 1000).toStringAsFixed(1)} km away";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("Incident History",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection("reports")
            .orderBy("createdAt", descending: true)
            .limit(500)
            .snapshots(),
        builder: (context, snap) {
          final all = snap.data?.docs ?? [];
          final docs = all.where((d) => _matches(d.data())).toList();

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _filters()),
              SliverToBoxAdapter(child: _summary(docs)),
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData)
                const SliverFillRemaining(
                  child: Center(
                      child: CircularProgressIndicator(color: Colors.white)),
                )
              else if (snap.hasError)
                SliverFillRemaining(
                  child: Center(
                    child: Text("Couldn't load reports.\n${snap.error}",
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54)),
                  ),
                )
              else if (docs.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(30),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off,
                              color: Colors.white38, size: 56),
                          SizedBox(height: 10),
                          Text("No reports match these filters",
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  sliver: SliverList.builder(
                    itemCount: docs.length,
                    itemBuilder: (_, i) => _reportCard(docs[i]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ---------------- Filters ----------------
  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchC,
            style: const TextStyle(color: Colors.white),
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: InputDecoration(
              hintText: "Search area, description...",
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () {
                        _searchC.clear();
                        setState(() => _query = "");
                      },
                    ),
              filled: true,
              fillColor: _card,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _chipRow(_categories, _category, (v) => setState(() => _category = v),
              withIcons: true),
          const SizedBox(height: 8),
          _chipRow(_statuses, _status, (v) => setState(() => _status = v)),
          const SizedBox(height: 8),
          _chipRow(_dates, _date, (v) => setState(() => _date = v)),
          if (_status == "Rejected")
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                "Rejected reports are private — only your own are shown.",
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chipRow(List<String> items, String selected, ValueChanged<String> on,
      {bool withIcons = false}) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _chip(it, it == selected, () => on(it), withIcons),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, bool withIcon) {
    final color = withIcon && label != "All"
        ? (MyReportsScreen.categoryColors[label] ?? Colors.white)
        : label == "Rejected"
            ? Colors.redAccent
            : label == "Verified"
                ? _green
                : Colors.white;
    return Material(
      color: selected ? color : _card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? color : Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (withIcon) ...[
                Icon(
                  label == "All"
                      ? Icons.layers
                      : (MyReportsScreen.categoryIcons[label] ?? Icons.warning),
                  size: 16,
                  color: selected ? _bg : color,
                ),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: TextStyle(
                      color: selected ? _bg : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- Summary ----------------
  Widget _summary(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final counts = <String, int>{};
    for (final d in docs) {
      final c = (d.data()["category"] ?? "").toString();
      counts[c] = (counts[c] ?? 0) + 1;
    }
    String top = "—";
    if (counts.isNotEmpty) {
      final e = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      top = "${e.first.key} (${e.first.value})";
    }
    final verified =
        docs.where((d) => _isVerified((d.data()["status"] ?? "").toString())).length;

    Widget stat(String v, String l, Color c) => Expanded(
          child: Column(
            children: [
              Text(v,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(l,
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
        );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          stat("${docs.length}", "Reports", Colors.white),
          stat("$verified", "Verified", _green),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Text(top,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text("Most reported",
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Report card ----------------
  Widget _reportCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final category = (d["category"] ?? "Incident").toString();
    final status = (d["status"] ?? "Pending").toString();
    final icon = MyReportsScreen.categoryIcons[category] ?? Icons.report_problem;
    final color = MyReportsScreen.categoryColors[category] ?? Colors.blueGrey;
    final address = (d["address"] ?? "").toString();
    final desc = (d["description"] ?? "").toString();
    final dist = _distance(d);
    final mine = d["userId"] == _uid;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => IncidentDetailScreen(data: d, docId: doc.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(category,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                          ),
                          _badge(_statusLabel(status),
                              MyReportsScreen.statusColor(status)),
                        ],
                      ),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          if (address.isNotEmpty)
                            _meta(Icons.place, address),
                          _meta(Icons.schedule,
                              MyReportsScreen.formatTimestamp(
                                  d["createdAt"] is Timestamp
                                      ? d["createdAt"] as Timestamp
                                      : null)),
                          if (dist.isNotEmpty) _meta(Icons.near_me, dist),
                          if (mine) _meta(Icons.person, "Your report"),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData i, String t) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(i, size: 13, color: Colors.white38),
          const SizedBox(width: 3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(t,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ),
        ],
      );
}

Widget _badge(String text, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c),
      ),
      child: Text(text,
          style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold)),
    );

// =====================================================
// Incident detail
// =====================================================
class IncidentDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  const IncidentDetailScreen(
      {super.key, required this.data, required this.docId});

  @override
  Widget build(BuildContext context) {
    final d = data;
    final category = (d["category"] ?? "Incident").toString();
    final status = (d["status"] ?? "Pending").toString();
    final statusColor = MyReportsScreen.statusColor(status);
    final color = MyReportsScreen.categoryColors[category] ?? Colors.blueGrey;
    final icon = MyReportsScreen.categoryIcons[category] ?? Icons.report_problem;
    final imageUrl = (d["imageUrl"] ?? "").toString();
    final address = (d["address"] ?? "").toString();
    final desc = (d["description"] ?? "").toString();
    final lat = (d["latitude"] as num?)?.toDouble();
    final lng = (d["longitude"] as num?)?.toDouble();
    final conf = (d["confidence"] as num?)?.toDouble();
    final aive = d["aive"] is Map
        ? Map<String, dynamic>.from(d["aive"] as Map)
        : <String, dynamic>{};
    final flags = (aive["flags"] as List?)?.map((e) => e.toString()).toList() ??
        <String>[];
    // Every AIVE check with pass / fail + reason (reports from version 5 on)
    final checks = ((aive["checks"] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final failed = checks.where((c) => c["passed"] != true).toList();
    final ts = d["createdAt"];
    String when = "";
    if (ts is Timestamp) {
      final t = ts.toDate();
      final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
      when = "${t.day}/${t.month}/${t.year} · "
          "$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? "AM" : "PM"}";
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("Incident Details",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          // Photo
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: imageUrl.isEmpty
                ? Container(
                    height: 170,
                    color: _card,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.image_not_supported,
                              color: Colors.white38, size: 40),
                          SizedBox(height: 6),
                          Text("No photo",
                              style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                    ),
                  )
                : Image.network(
                    imageUrl,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (c, w, p) => p == null
                        ? w
                        : Container(
                            height: 220,
                            color: _card,
                            child: const Center(
                                child: CircularProgressIndicator(
                                    color: Colors.white)),
                          ),
                    errorBuilder: (_, __, ___) => Container(
                      height: 170,
                      color: _card,
                      child: const Center(
                          child: Icon(Icons.broken_image,
                              color: Colors.white38, size: 40)),
                    ),
                  ),
          ),
          const SizedBox(height: 14),

          // Title + status
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(category,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ),
              _badge(_statusLabel(status), statusColor),
            ],
          ),
          const SizedBox(height: 12),
          if (desc.isNotEmpty)
            Text(desc,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, height: 1.4)),
          const SizedBox(height: 12),
          _infoRow(Icons.place, address.isEmpty ? "Address not available" : address),
          if (when.isNotEmpty) _infoRow(Icons.schedule, when),
          if (lat != null && lng != null)
            _infoRow(Icons.gps_fixed,
                "${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}"),
          const SizedBox(height: 14),

          // Map
          if (lat != null && lng != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 180,
                child: GoogleMap(
                  initialCameraPosition:
                      CameraPosition(target: LatLng(lat, lng), zoom: 15.5),
                  markers: {
                    Marker(
                      markerId: const MarkerId("incident"),
                      position: LatLng(lat, lng),
                      infoWindow: InfoWindow(title: category),
                    ),
                  },
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                  mapToolbarEnabled: false,
                  liteModeEnabled: true,
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MapScreen(
                    focusLat: lat,
                    focusLng: lng,
                    focusTitle: category,
                    focusSnippet: desc.isNotEmpty ? desc : address,
                  ),
                ),
              ),
              icon: const Icon(Icons.map),
              label: const Text("Open on Live Map"),
            ),
            const SizedBox(height: 16),
          ],

          // AIVE verification
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified_user, color: Colors.white70),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text("AI Verification (AIVE)",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                    _badge(_statusLabel(status), statusColor),
                  ],
                ),
                const SizedBox(height: 12),
                if (conf == null)
                  const Text("Submitted before AI verification was added.",
                      style: TextStyle(color: Colors.white54))
                else ...[
                  // Verification score (points) and photo AI confidence (%)
                  // are different numbers and are labelled separately.
                  _scoreBar("Verification score", conf, statusColor,
                      big: true, outOf: 100),
                  if (aive["imageScore"] is num)
                    _scoreBar("Photo AI confidence",
                        (aive["imageScore"] as num).toDouble(),
                        Colors.lightBlueAccent),
                  if (aive["gpsScore"] is num)
                    _scoreBar("Location", (aive["gpsScore"] as num).toDouble(),
                        Colors.lightBlueAccent,
                        outOf: 25),
                  if (aive["descriptionScore"] is num)
                    _scoreBar("Description",
                        (aive["descriptionScore"] as num).toDouble(),
                        Colors.lightBlueAccent,
                        outOf: 15),
                  if (aive["timeScore"] is num)
                    _scoreBar("Time", (aive["timeScore"] as num).toDouble(),
                        Colors.lightBlueAccent,
                        outOf: 10),
                  if (aive["nearbyScore"] is num)
                    _scoreBar("Nearby reports",
                        (aive["nearbyScore"] as num).toDouble(),
                        Colors.lightBlueAccent,
                        outOf: 10),
                  if (checks.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    if (failed.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          "Rejected because: "
                          "${failed.map((c) => c["name"]).join(", ")}",
                          style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5),
                        ),
                      ),
                    for (final c in checks)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              c["passed"] == true
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              size: 16,
                              color: c["passed"] == true
                                  ? _green
                                  : Colors.redAccent,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                "${c["name"]}"
                                "${c["maxPoints"] != null ? " (${c["points"]}/${c["maxPoints"]})" : ""}"
                                ": ${c["detail"]}",
                                style: TextStyle(
                                    color: c["passed"] == true
                                        ? Colors.white70
                                        : Colors.redAccent,
                                    fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ] else if (flags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final f in flags)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text("• $f",
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 12)),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData i, String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(i, size: 18, color: Colors.white54),
            const SizedBox(width: 8),
            Expanded(
                child: Text(t, style: const TextStyle(color: Colors.white70))),
          ],
        ),
      );

  /// [outOf] = show points ("36/40"); without it the value is a % (AI
  /// confidence).
  Widget _scoreBar(String label, double v, Color c,
      {bool big = false, int? outOf}) {
    final value = v.clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: big ? 13 : 12,
                    fontWeight: big ? FontWeight.bold : FontWeight.normal)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: value,
                minHeight: big ? 10 : 7,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation(c),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: Text(
                outOf == null
                    ? "${(value * 100).round()}%"
                    : "${(value * outOf).round()}/$outOf",
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
