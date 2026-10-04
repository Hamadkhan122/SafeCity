// SafeCity - Safety Score Screen (M4, UC-08)
// =====================================================
// Search any area (Google Places autocomplete) and see its safety score for
// the chosen radius (1 / 2 / 3 / 5 km chips, default 3 km). Opens on the
// user's current location. Only incidents inside the chosen radius are
// shown and counted.
//
// Score = SafetyScoreService.scoreAt(chosen radius) - the same algorithm the
// heatmap zones and the safe route use (see safety_score_service.dart):
//   start at 100, each incident takes away:
//   category points (Fire 35, Accident 30, Fight 25, Harassment 20,
//   Road Damage 10) x time (today 100 %, 2-7 d 70 %, 8-30 d 40 %,
//   31-90 d 20 %) x distance (inner / middle / outer third of the radius:
//   100 / 60 / 30 %) x trust (Verified 1.0, Rejected 0)
//   duplicates of one incident (< 150 m, < 6 h) count once
//   score = 100 - points lost; 70-100 Safe, 40-69 Moderate, 0-39 Unsafe

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/incident_model.dart';
import '../services/places_service.dart';
import '../services/safety_score_service.dart';
import '../widgets/search_bar_widget.dart';
import 'my_reports_screen.dart';

const _bg = Color(0xff071B52);
const _card = Color(0xff0E2A6B);

class SafetyScoreScreen extends StatefulWidget {
  const SafetyScoreScreen({super.key});

  @override
  State<SafetyScoreScreen> createState() => _SafetyScoreScreenState();
}

class _SafetyScoreScreenState extends State<SafetyScoreScreen> {
  /// Radius options (km) shown as chips under the search bar.
  static const List<int> _radiusOptionsKm = [1, 2, 3, 5];
  double _radius = SafetyScoreService.searchRadiusMeters; // default 3 km

  String get _radiusLabel => _fmtDist(_radius);

  /// Map zoom that shows the whole circle for the chosen radius.
  double get _zoom {
    if (_radius <= 1000) return 14.2;
    if (_radius <= 2000) return 13.3;
    if (_radius <= 3000) return 12.8;
    return 12.0;
  }

  static String _fmtDist(double m) {
    if (m < 1000) return "${m.round()} m";
    final km = m / 1000;
    return km == km.roundToDouble()
        ? "${km.round()} km"
        : "${km.toStringAsFixed(1)} km";
  }

  void _setRadius(int km) {
    setState(() => _radius = km * 1000.0);
    _recompute();
    if (_point != null) {
      _map?.animateCamera(CameraUpdate.newLatLngZoom(_point!, _zoom));
    }
  }

  final PlacesService _places = PlacesService();
  final TextEditingController _searchCtrl = TextEditingController();
  GoogleMapController? _map;
  StreamSubscription<QuerySnapshot>? _sub;
  Timer? _debounce;
  String? _mapStyle;

  List<IncidentModel> _incidents = [];
  List<dynamic> _results = [];
  bool _searching = false;
  bool _loadingLocation = true;

  LatLng? _point; // area being scored
  String _placeName = "Your current area";
  SafetyResult? _result;

  @override
  void initState() {
    super.initState();
    _loadStyle();
    _sub = FirebaseFirestore.instance.collection("reports").snapshots().listen(
      (snap) {
        _incidents = IncidentModel.listFromDocs(snap.docs);
        _recompute();
      },
      onError: (e) => debugPrint("safety score stream error: $e"),
    );
    _useMyLocation();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStyle() async {
    try {
      final s = await rootBundle.loadString("assets/map_styles/night_style.json");
      if (mounted) setState(() => _mapStyle = s);
    } catch (_) {}
  }

  Future<void> _useMyLocation() async {
    setState(() => _loadingLocation = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings:
                const LocationSettings(accuracy: LocationAccuracy.high),
          );
      _setPoint(LatLng(pos.latitude, pos.longitude), "Your current area");
    } catch (e) {
      debugPrint("safety score location error: $e");
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  void _setPoint(LatLng p, String name) {
    _point = p;
    _placeName = name;
    // Tapped on the map -> show the area's real name instead.
    if (name == "Selected location") _nameFromCoordinates(p);
    _recompute();
    _map?.animateCamera(CameraUpdate.newLatLngZoom(p, _zoom));
  }

  Future<void> _nameFromCoordinates(LatLng p) async {
    try {
      final marks = await placemarkFromCoordinates(p.latitude, p.longitude);
      if (marks.isEmpty || _point != p) return;
      final m = marks.first;
      final parts = <String>[];
      for (final x in [m.subLocality, m.locality, m.subAdministrativeArea]) {
        final t = (x ?? "").trim();
        if (t.isNotEmpty && !parts.contains(t)) parts.add(t);
        if (parts.length == 2) break;
      }
      if (parts.isNotEmpty && mounted) {
        setState(() => _placeName = parts.join(", "));
      }
    } catch (_) {}
  }

  void _recompute() {
    if (_point == null) {
      if (mounted) setState(() {});
      return;
    }
    final r = SafetyScoreService.scoreAt(
      lat: _point!.latitude,
      lng: _point!.longitude,
      incidents: _incidents,
      radiusMeters: _radius,
    );
    if (mounted) setState(() => _result = r);
  }

  // ---------------- Search ----------------
  int _searchToken = 0;

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    final token = ++_searchToken;
    if (v.trim().length < 2) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted || token != _searchToken) return;
      setState(() => _searching = true);
      final r = await _places.searchPlaces(v.trim());
      if (!mounted || token != _searchToken) return;
      setState(() {
        _results = r;
        _searching = false;
      });
    });
  }

  Future<void> _onResultTap(Map<String, dynamic> item) async {
    _debounce?.cancel();
    _searchToken++;
    _searching = false;
    FocusScope.of(context).unfocus();
    if (item["lat"] is num && item["lng"] is num) {
      final desc = (item["description"] ?? "Selected area").toString();
      setState(() {
        _results = [];
        _searchCtrl.text = desc;
      });
      _setPoint(LatLng((item["lat"] as num).toDouble(),
          (item["lng"] as num).toDouble()), desc);
      return;
    }
    final placeId = item["place_id"]?.toString();
    final desc = (item["description"] ?? "Selected area").toString();
    setState(() {
      _results = [];
      _searchCtrl.text = desc;
    });
    if (placeId == null) return;
    final details = await _places.getPlaceLocation(placeId);
    final loc = details?["geometry"]?["location"];
    if (loc == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't find that place")),
        );
      }
      return;
    }
    _setPoint(
      LatLng((loc["lat"] as num).toDouble(), (loc["lng"] as num).toDouble()),
      (details?["name"] ?? desc).toString(),
    );
  }

  // ---------------- Data helpers ----------------
  /// Public incidents inside the chosen circle (for markers + ring counts).
  List<IncidentModel> get _nearby {
    if (_point == null) return [];
    return _incidents.where((i) {
      if (!SafetyScoreService.isPublicStatus(i.status)) return false;
      if (!SafetyScoreService.isSupportedCategory(i.category)) return false;
      return SafetyScoreService.distanceMeters(
              _point!.latitude, _point!.longitude, i.latitude, i.longitude) <=
          _radius;
    }).toList();
  }

  /// Incidents in 3 equal distance bands of the chosen radius.
  List<int> _ringCounts(List<IncidentModel> list) {
    final c = [0, 0, 0];
    final band = _radius / 3;
    for (final i in list) {
      final d = SafetyScoreService.distanceMeters(
          _point!.latitude, _point!.longitude, i.latitude, i.longitude);
      final k = (d / band).floor();
      c[k > 2 ? 2 : k]++;
    }
    return c;
  }

  double _hueFor(String cat) {
    switch (cat) {
      case "Accident":
        return BitmapDescriptor.hueRed;
      case "Fire":
        return BitmapDescriptor.hueOrange;
      case "Fight":
        return BitmapDescriptor.hueYellow;
      case "Harassment":
        return BitmapDescriptor.hueRose;
      case "Road Damage":
        return BitmapDescriptor.hueGreen;
    }
    return BitmapDescriptor.hueViolet;
  }

  // ---------------- UI ----------------
  // Full-screen map (like the Live Map) + search bar on top + a compact
  // score card at the bottom. Tapping the card opens the full details.
  @override
  Widget build(BuildContext context) {
    final nearby = _nearby;
    final color = _result?.color ?? Colors.white;

    final circles = <Circle>{
      if (_point != null)
        Circle(
          circleId: const CircleId("radius"),
          center: _point!,
          radius: _radius,
          fillColor: color.withValues(alpha: 0.12),
          strokeColor: color,
          strokeWidth: 2,
        ),
    };
    final markers = <Marker>{
      if (_point != null)
        Marker(
          markerId: const MarkerId("center"),
          position: _point!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(title: _placeName),
        ),
      for (final i in nearby)
        Marker(
          markerId: MarkerId("inc_${i.id}"),
          position: LatLng(i.latitude, i.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(_hueFor(i.category)),
          infoWindow: InfoWindow(title: i.category, snippet: i.status),
        ),
    };

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("Safety Score",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: "How is it calculated?",
            icon: const Icon(Icons.info_outline),
            onPressed: _showCriteria,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(34.1688, 73.2215), // Abbottabad
              zoom: 12.8,
            ),
            style: _mapStyle,
            circles: circles,
            markers: markers,
            onMapCreated: (c) {
              _map = c;
              if (_point != null) {
                c.moveCamera(CameraUpdate.newLatLngZoom(_point!, _zoom));
              }
            },
            // Tap anywhere on the map to check that spot.
            onTap: (p) {
              if (_results.isNotEmpty) {
                FocusScope.of(context).unfocus();
                setState(() => _results = []);
                return;
              }
              _setPoint(p, "Selected location");
            },
            myLocationEnabled: true,
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
          ),

          // Radius chips (1 / 2 / 3 / 5 km) - placed before the search bar so
          // search results cover them.
          Positioned(
            top: 72,
            left: 15,
            right: 15,
            child: Row(
              children: [
                for (final km in _radiusOptionsKm)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text("$km km"),
                      selected: _radius == km * 1000.0,
                      onSelected: (_) => _setRadius(km),
                      selectedColor: const Color(0xff0A2E73),
                      backgroundColor: _card,
                      labelStyle: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                      side: BorderSide(
                          color: _radius == km * 1000.0
                              ? Colors.white
                              : Colors.white24),
                      showCheckmark: false,
                    ),
                  ),
              ],
            ),
          ),

          // Search bar
          Positioned(
            top: 12,
            left: 15,
            right: 15,
            child: SearchBarWidget(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              results: _results,
              searching: _searching,
              onResultTap: _onResultTap,
            ),
          ),

          // My location
          Positioned(
            right: 15,
            bottom: 140,
            child: FloatingActionButton(
              heroTag: "ss_me",
              backgroundColor: const Color(0xff0A2E73),
              tooltip: "My location",
              onPressed: () {
                _searchCtrl.clear();
                setState(() => _results = []);
                _useMyLocation();
              },
              child: const Icon(Icons.my_location, color: Colors.white),
            ),
          ),

          // Compact score card -> tap for details
          Positioned(
            left: 15,
            right: 15,
            bottom: 20,
            child: _result == null
                ? _box(
                    child: Center(
                      child: _loadingLocation
                          ? const SizedBox(
                              height: 26,
                              width: 26,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 3))
                          : const Text(
                              "Search an area or tap the map to see its score.",
                              style: TextStyle(color: Colors.white70)),
                    ),
                  )
                : _summaryCard(_result!),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(SafetyResult r) {
    return Material(
      color: _card,
      elevation: 8,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _openDetails,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: r.color.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 58,
                height: 58,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 58,
                      height: 58,
                      child: CircularProgressIndicator(
                        value: r.score / 100,
                        strokeWidth: 6,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation(r.color),
                      ),
                    ),
                    Text("${r.score}",
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_placeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: r.color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: r.color),
                          ),
                          child: Text(r.label,
                              style: TextStyle(
                                  color: r.color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text("${r.incidentCount} incident(s) · $_radiusLabel",
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.keyboard_arrow_up, color: Colors.white70),
                  Text("Details",
                      style: TextStyle(color: Colors.white54, fontSize: 10)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetails() {
    final r = _result;
    if (r == null) return;
    final rings = _ringCounts(_nearby);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        maxChildSize: 0.92,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Center(
              child: Container(
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _scoreCard(r),
            const SizedBox(height: 12),
            _ringsCard(rings),
            const SizedBox(height: 12),
            _breakdownCard(r),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _showCriteria,
              icon: const Icon(Icons.info_outline),
              label: const Text("How is the score calculated?"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _box({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: child,
      );

  Widget _scoreCard(SafetyResult r) {
    return _box(
      child: Row(
        children: [
          SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: r.score / 100),
                    duration: const Duration(milliseconds: 700),
                    builder: (_, v, __) => CircularProgressIndicator(
                      value: v,
                      strokeWidth: 8,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(r.color),
                    ),
                  ),
                ),
                Text("${r.score}",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_placeName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: r.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: r.color),
                  ),
                  child: Text(r.label,
                      style: TextStyle(
                          color: r.color, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 6),
                Text("${r.incidentCount} incident(s) within $_radiusLabel",
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ringsCard(List<int> c) {
    Widget ring(String label, int n) => Expanded(
          child: Column(
            children: [
              Text("$n",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(color: Colors.white60, fontSize: 11)),
            ],
          ),
        );
    return _box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Distance from centre",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(children: [
            ring("0 – ${_fmtDist(_radius / 3)}", c[0]),
            ring("${_fmtDist(_radius / 3)} – ${_fmtDist(_radius * 2 / 3)}", c[1]),
            ring("${_fmtDist(_radius * 2 / 3)} – $_radiusLabel", c[2]),
          ]),
          const SizedBox(height: 8),
          const Text("Closer incidents affect the score more.",
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _breakdownCard(SafetyResult r) {
    final entries = r.categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("What is reported here",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            const Text("No reported incidents in this area.",
                style: TextStyle(color: Colors.white70))
          else
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(MyReportsScreen.categoryIcons[e.key] ?? Icons.warning,
                        color: MyReportsScreen.categoryColors[e.key] ??
                            Colors.white,
                        size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(e.key,
                            style: const TextStyle(color: Colors.white))),
                    Text("${e.value}",
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  void _showCriteria() {
    Widget row(String a, String b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 95,
                  child: Text(a,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold))),
              Expanded(
                  child: Text(b, style: const TextStyle(color: Colors.white70))),
            ],
          ),
        );
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("How the score is calculated",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
              "Every area starts at 100. Each incident inside the "
              "radius takes points away:",
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            row("Category", "Fire −35 · Accident −30 · Fight −25 · Harassment −20 · Road Damage −10"),
            row("Time", "Today 100% · 2–7 days 70% · 8–30 days 40% · 31–90 days 20% · older 0%"),
            row("Distance",
                "Inner ⅓ of $_radiusLabel 100% · middle ⅓ 60% · outer ⅓ 30%"),
            row("Trust", "Only AI-verified reports count · Rejected ignored"),
            row("Duplicates", "Many reports of the same incident count once (+25% each, max +50%)"),
            const SizedBox(height: 10),
            const Text(
              "Score = 100 − points lost\n"
              "70 – 100 Safe  ·  40 – 69 Moderate  ·  0 – 39 Unsafe\n"
              "Example: a fire reported here today → 100 − 35 = 65 (Moderate)",
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
