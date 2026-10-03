// SafeCity - Heatmap Visualization Screen (UC-07, FR-HM-01..03)
// =====================================================
// Reads the SAME "reports" Firestore collection MapScreen streams.
// Only AIVE "Suspicious" (or "Rejected") reports are hidden.
//
// ZONE RISK (same algorithm as the Safety Score and Safe Route)
//  - Reports are grouped into zones around the most serious incidents
//    (every report within 500 m of a zone centre joins that zone), so one
//    hotspot is never split into two weak zones.
//  - Zone level = SafetyScoreService score at the zone centre (700 m), which
//    weighs severity, recency (per incident type), AIVE trust and merges
//    duplicate reports of the same incident:
//      Low 85-100 · Medium 70-84 · Med-high 40-69 · High 0-39 (safety score)
//    So 2 fresh fires rank above 8 old road-damage reports.
//  - "Major only" (default ON) hides Low zones. Turn it off from the chip
//    to see every zone.
//  - At most [_maxZones] zones (highest risk first) are drawn.
//
// Features
//  - Each zone = solid core + animated pulsing ring (higher risk = stronger
//    and faster pulse). The selected zone pulses in white on top.
//  - Camera automatically fits all zones, so hotspots are never off-screen.
//  - Category chips with counts: tapping one filters the map, flies the
//    camera to those incidents and makes them pulse.
//  - Bottom carousel lists every zone (sorted by risk). Swipe/tap a card ->
//    camera flies there; tap a zone circle or "Details" -> breakdown sheet
//    with category bars and the latest reports.
//  - UC-07 alt flow 2.1: "No incident data available." when empty.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../models/incident_model.dart';
import '../services/places_service.dart';
import '../services/safety_score_service.dart';
import '../widgets/search_bar_widget.dart';
import 'map_screen.dart';
import 'my_reports_screen.dart';
import 'sos_screen.dart';

const _bg = Color(0xff071B52);
const _card = Color(0xff0E2A6B);

const _categories = [
  "All",
  "Accident",
  "Fire",
  "Harassment",
  "Road Damage",
  "Fight",
];

class _RiskLevel {
  final String label;
  final String range;
  final Color color;
  final double pulseSpeed;
  final double pulseStrength;
  const _RiskLevel(
      this.label, this.range, this.color, this.pulseSpeed, this.pulseStrength);
}

// range = zone safety score (0-100, higher = safer)
const _low = _RiskLevel("Low", "85–100", Color(0xff66BB6A), 0.6, 0.35);
const _medium = _RiskLevel("Medium", "70–84", Color(0xffFBC02D), 0.8, 0.5);
const _mediumHigh = _RiskLevel("Med-high", "40–69", Color(0xffFF8F00), 1.0, 0.65);
const _high = _RiskLevel("High", "0–39", Color(0xffD32F2F), 1.4, 0.85);
const _levels = [_low, _medium, _mediumHigh, _high];

const int _maxZones = 15;
const double _clusterMeters = 500; // reports this close join one zone
const double _zoneScoreRadius = 700; // radius used for the zone score

_RiskLevel _levelForScore(int score) {
  if (score < 40) return _high;
  if (score < 70) return _mediumHigh;
  if (score < 85) return _medium;
  return _low;
}

/// Firestore map -> IncidentModel (for SafetyScoreService).
IncidentModel _toIncident(Map<String, dynamic> d) {
  final ts = d["createdAt"];
  return IncidentModel(
    id: (d["_id"] ?? "").toString(),
    reportId: (d["reportId"] ?? "").toString(),
    category: (d["category"] ?? "").toString(),
    description: (d["description"] ?? "").toString(),
    latitude: (d["latitude"] as num).toDouble(),
    longitude: (d["longitude"] as num).toDouble(),
    address: (d["address"] ?? "").toString(),
    gpsAccuracy: (d["gpsAccuracy"] as num?)?.toDouble() ?? 0,
    imageUrl: (d["imageUrl"] ?? "").toString(),
    status: (d["status"] ?? "Pending").toString(),
    createdAt: ts is Timestamp ? ts.toDate() : null,
    userId: d["userId"]?.toString(),
  );
}

class _Zone {
  final String key;
  final LatLng center;
  final List<Map<String, dynamic>> reports;
  final _RiskLevel level;
  final int score; // zone safety score (0-100, higher = safer)
  final String name;
  final Map<String, int> categoryCounts;

  _Zone({
    required this.key,
    required this.center,
    required this.reports,
    required this.level,
    required this.score,
    required this.name,
    required this.categoryCounts,
  });

  int get count => reports.length;

  String get topCategories {
    final e = categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return e.take(2).map((x) => "${x.key} ${x.value}").join(" · ");
  }
}

class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen>
    with SingleTickerProviderStateMixin {
  // Fixed zone size (~1.1 km) so zones don't change while zooming.
  static const double _zoneSize = 0.01;
  static const double _zoneRadius = 450; // metres

  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  GoogleMapController? mapController;
  final PageController _pageController = PageController(viewportFraction: 0.86);

  StreamSubscription<QuerySnapshot>? _incidentSub;
  List<Map<String, dynamic>> _allReports = [];

  String selectedFilter = "All";
  bool _majorOnly = true; // hide Low-risk zones
  bool loading = true;
  bool _legendOpen = true; // old version: legend always visible
  bool _didInitialFit = false;
  String? _mapStyle;
  Position? _myPosition;

  List<_Zone> _zones = [];
  String? _selectedKey;
  Set<Circle> heatCircles = {};

  late final AnimationController _pulse;
  Timer? _mapPulseTimer;
  // Pause circle animation while the user drags/zooms -> map stays smooth.
  bool _cameraMoving = false;

  // ---- Area search ----
  final PlacesService _places = PlacesService();
  final TextEditingController _searchC = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _searching = false;
  Timer? _searchDebounce;
  int _searchToken = 0;
  Marker? _searchMarker;

  static const CameraPosition _defaultPosition = CameraPosition(
    target: LatLng(34.1688, 73.2215),
    zoom: 12,
  );

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _mapPulseTimer = Timer.periodic(
      const Duration(milliseconds: 140),
      (_) => _updatePulseCircles(),
    );
    _loadMapStyle();
    _listenIncidents();
    _loadMyPosition();
  }

  @override
  void dispose() {
    _mapPulseTimer?.cancel();
    _pulse.dispose();
    _pageController.dispose();
    _searchDebounce?.cancel();
    _searchC.dispose();
    _incidentSub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------
  Future<void> _loadMapStyle() async {
    try {
      final style =
          await rootBundle.loadString("assets/map_styles/night_style.json");
      if (mounted) setState(() => _mapStyle = style);
    } catch (e) {
      debugPrint("heatmap style error: $e");
    }
  }

  Future<void> _loadMyPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
        return;
      }
      _myPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Heatmap location error: $e");
    }
  }

  void _listenIncidents() {
    _incidentSub = firestore.collection("reports").snapshots().listen(
      (snapshot) {
        _allReports = [];
        for (final doc in snapshot.docs) {
          final d = doc.data();
          if (d["latitude"] == null || d["longitude"] == null) continue;
          if (!SafetyScoreService.isPublicReport(d)) continue;
          _allReports.add({...d, "_id": doc.id});
        }
        _rebuildZones();
        if (mounted) setState(() => loading = false);
        if (!_didInitialFit && _zones.isNotEmpty) {
          _didInitialFit = true;
          _fitToZones();
        }
      },
      onError: (e) {
        debugPrint("Heatmap incident stream error: $e");
        if (mounted) setState(() => loading = false);
      },
    );
  }

  List<Map<String, dynamic>> get _filteredReports => selectedFilter == "All"
      ? _allReports
      : _allReports.where((d) => d["category"] == selectedFilter).toList();

  int _countFor(String category) => category == "All"
      ? _allReports.length
      : _allReports.where((d) => d["category"] == category).length;

  void _rebuildZones() {
    final reports = _filteredReports;
    final incidents = reports.map(_toIncident).toList();
    final now = DateTime.now();

    // Seeds = most serious reports first (severity x recency x trust).
    final order = List<int>.generate(reports.length, (i) => i)
      ..sort((a, b) {
        double w(int k) => SafetyScoreService.incidentRisk(
            incidents[k].category,
            incidents[k].createdAt,
            SafetyScoreService.trustFor(incidents[k].status),
            now);
        return w(b).compareTo(w(a));
      });

    final assigned = List<bool>.filled(reports.length, false);
    final zones = <_Zone>[];
    for (final seed in order) {
      if (assigned[seed]) continue;
      final members = <int>[];
      for (final k in order) {
        if (assigned[k]) continue;
        if (SafetyScoreService.distanceMeters(
                incidents[seed].latitude,
                incidents[seed].longitude,
                incidents[k].latitude,
                incidents[k].longitude) <=
            _clusterMeters) {
          assigned[k] = true;
          members.add(k);
        }
      }

      double lat = 0, lng = 0;
      final cats = <String, int>{};
      final names = <String, int>{};
      for (final k in members) {
        final d = reports[k];
        lat += incidents[k].latitude;
        lng += incidents[k].longitude;
        final c = incidents[k].category;
        cats[c] = (cats[c] ?? 0) + 1;
        final a = (d["address"] ?? "").toString().trim();
        if (a.isNotEmpty) names[a] = (names[a] ?? 0) + 1;
      }
      final n = members.length;
      final center = LatLng(lat / n, lng / n);

      // Same algorithm as the Safety Score screen and Safe Route.
      final score = SafetyScoreService.scoreAt(
        lat: center.latitude,
        lng: center.longitude,
        incidents: incidents,
        radiusMeters: _zoneScoreRadius,
        now: now,
      ).score;
      final level = _levelForScore(score);
      if (_majorOnly && level == _low) continue; // minor zone

      String name;
      if (names.isNotEmpty) {
        final best = names.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        name = best.first.key;
      } else {
        name = "Area ${center.latitude.toStringAsFixed(3)}, "
            "${center.longitude.toStringAsFixed(3)}";
      }
      zones.add(_Zone(
        key: (reports[seed]["_id"] ?? "$seed").toString(),
        center: center,
        reports: [for (final k in members) reports[k]],
        level: level,
        score: score,
        name: name,
        categoryCounts: cats,
      ));
    }

    zones.sort((a, b) => a.score.compareTo(b.score)); // highest risk first
    _zones = zones.take(_maxZones).toList();
    if (_selectedKey != null && !zones.any((z) => z.key == _selectedKey)) {
      _selectedKey = null;
    }
    _updatePulseCircles(force: true);
  }

  // ---------------------------------------------------------------
  // Camera
  // ---------------------------------------------------------------
  void _fitToZones() {
    if (mapController == null || _zones.isEmpty) return;
    if (_zones.length == 1) {
      mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(_zones.first.center, 14.5));
      return;
    }
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final z in _zones) {
      minLat = math.min(minLat, z.center.latitude);
      maxLat = math.max(maxLat, z.center.latitude);
      minLng = math.min(minLng, z.center.longitude);
      maxLng = math.max(maxLng, z.center.longitude);
    }
    mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - 0.01, minLng - 0.01),
          northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
        ),
        60,
      ),
    );
  }

  void _selectZone(_Zone z, {bool fromCarousel = false}) {
    setState(() => _selectedKey = z.key);
    mapController?.animateCamera(CameraUpdate.newLatLngZoom(z.center, 15));
    if (!fromCarousel) {
      final i = _zones.indexWhere((x) => x.key == z.key);
      if (i >= 0 && _pageController.hasClients) {
        _pageController.animateToPage(
          i,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void _onFilter(String category) {
    setState(() {
      selectedFilter = category;
      _selectedKey = null;
    });
    _rebuildZones();
    if (_pageController.hasClients && _zones.isNotEmpty) {
      _pageController.jumpToPage(0);
    }
    _fitToZones();
  }

  // ---------------------------------------------------------------
  // Animated circles (~12 fps)
  // ---------------------------------------------------------------
  void _updatePulseCircles({bool force = false}) {
    if (!mounted) return;
    if (_zones.isEmpty && !force) return;
    if (_cameraMoving && !force) return;

    final t = _pulse.value;
    final circles = <Circle>{};

    for (final z in _zones) {
      final selected = z.key == _selectedKey;
      final phase = (t * z.level.pulseSpeed) % 1.0;
      final eased = Curves.easeOut.transform(phase);
      final strength = z.level.pulseStrength * (selected ? 1.6 : 1.0);

      circles.add(Circle(
        circleId: CircleId("pulse_${z.key}"),
        center: z.center,
        radius: _zoneRadius * (1 + strength * 1.5 * eased),
        fillColor: z.level.color.withValues(alpha: 0.35 * (1 - eased)),
        strokeColor: (selected ? Colors.white : z.level.color)
            .withValues(alpha: 0.7 * (1 - eased)),
        strokeWidth: selected ? 3 : 1,
        zIndex: 1,
      ));
      circles.add(Circle(
        circleId: CircleId("core_${z.key}"),
        center: z.center,
        radius: _zoneRadius,
        fillColor: z.level.color.withValues(alpha: selected ? 0.75 : 0.55),
        strokeColor: selected ? Colors.white : z.level.color,
        strokeWidth: selected ? 4 : 2,
        zIndex: 2,
        consumeTapEvents: true,
        onTap: () {
          _selectZone(z);
          _showZoneDetails(z);
        },
      ));
    }

    setState(() => heatCircles = circles);
  }

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final showEmpty = !loading && _zones.isEmpty;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "Incident Heatmap",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _defaultPosition,
            style: _mapStyle,
            circles: heatCircles,
            markers: {if (_searchMarker != null) _searchMarker!},
            onMapCreated: (c) {
              mapController = c;
              if (_zones.isNotEmpty) {
                _didInitialFit = true;
                _fitToZones();
              }
            },
            onCameraMoveStarted: () => _cameraMoving = true,
            onCameraIdle: () => _cameraMoving = false,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          if (loading)
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          if (showEmpty)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: _card.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  _allReports.isEmpty
                      ? "No incident data available."
                      : _majorOnly
                          ? (selectedFilter == "All"
                              ? "No major risk zones right now.\nTap \"Major only\" to see all zones."
                              : "No major $selectedFilter zones right now.")
                          : "No $selectedFilter reports yet.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),

          // Category chips with counts + summary
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Column(
              children: [
                // Search a specific area -> fly there and show its zones
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: SearchBarWidget(
                    controller: _searchC,
                    onChanged: _onSearchChanged,
                    results: _searchResults,
                    searching: _searching,
                    onResultTap: _onSearchResultTap,
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      _majorChip(),
                      for (final c in _categories) _categoryChip(c),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (!loading && _zones.isNotEmpty) _summaryBar(),
              ],
            ),
          ),

          // Right-side buttons — same look & order as the Live Map
          // (SOS red, layers white, green, my-location navy).
          Positioned(
            right: 15,
            bottom: _zones.isEmpty ? 20 : 170,
            child: Column(
              children: [
                FloatingActionButton(
                  heroTag: "hm_sos",
                  backgroundColor: Colors.red,
                  tooltip: "Emergency SOS",
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SosScreen()),
                  ),
                  child: const Icon(Icons.sos, color: Colors.white),
                ),
                const SizedBox(height: 14),
                FloatingActionButton(
                  heroTag: "hm_layers",
                  backgroundColor: Colors.white,
                  tooltip: "Risk levels",
                  onPressed: () => setState(() => _legendOpen = !_legendOpen),
                  child: const Icon(Icons.layers, color: Color(0xff0A2E73)),
                ),
                const SizedBox(height: 14),
                FloatingActionButton(
                  heroTag: "hm_fit",
                  backgroundColor: Colors.green,
                  tooltip: "Show all zones",
                  onPressed: () {
                    setState(() => _selectedKey = null);
                    _fitToZones();
                  },
                  child: const Icon(Icons.zoom_out_map, color: Colors.white),
                ),
                const SizedBox(height: 14),
                FloatingActionButton(
                  heroTag: "hm_me",
                  backgroundColor: const Color(0xff0A2E73),
                  tooltip: "My location",
                  onPressed: () {
                    if (_myPosition == null) return;
                    mapController?.animateCamera(CameraUpdate.newLatLngZoom(
                      LatLng(_myPosition!.latitude, _myPosition!.longitude),
                      14,
                    ));
                  },
                  child: const Icon(Icons.my_location, color: Colors.white),
                ),
              ],
            ),
          ),

          // Risk-level legend (bottom-left, like the old version);
          // the layers button hides/shows it.
          if (_legendOpen)
            Positioned(
              left: 12,
              bottom: _zones.isEmpty ? 20 : 172,
              child: _legend(),
            ),

          // Zone carousel
          if (_zones.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              height: 140,
              child: PageView.builder(
                controller: _pageController,
                itemCount: _zones.length,
                onPageChanged: (i) => _selectZone(_zones[i], fromCarousel: true),
                itemBuilder: (_, i) => _zoneCard(_zones[i], i),
              ),
            ),
        ],
      ),
    );
  }

  Widget _categoryChip(String c) {
    final selected = c == selectedFilter;
    final count = _countFor(c);
    final color = c == "All"
        ? Colors.white
        : (MyReportsScreen.categoryColors[c] ?? Colors.white);
    final icon = c == "All"
        ? Icons.layers
        : (MyReportsScreen.categoryIcons[c] ?? Icons.warning);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? color : _card.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _onFilter(c),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? color : Colors.white24),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: selected ? _bg : color),
                const SizedBox(width: 6),
                Text(
                  c,
                  style: TextStyle(
                    color: selected ? _bg : Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? _bg.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    "$count",
                    style: TextStyle(
                      color: selected ? _bg : Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _majorChip() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: _majorOnly ? const Color(0xffD32F2F) : _card.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            setState(() {
              _majorOnly = !_majorOnly;
              _selectedKey = null;
            });
            _rebuildZones();
            if (_pageController.hasClients && _zones.isNotEmpty) {
              _pageController.jumpToPage(0);
            }
            _fitToZones();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: _majorOnly ? const Color(0xffD32F2F) : Colors.white24),
            ),
            child: Row(
              children: [
                Icon(_majorOnly ? Icons.filter_alt : Icons.filter_alt_off,
                    size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  _majorOnly ? "Major only" : "All zones",
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Area search
  // ---------------------------------------------------------------
  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    final token = ++_searchToken;
    if (v.trim().length < 2) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted || token != _searchToken) return;
      setState(() => _searching = true);
      final r = await _places.searchPlaces(v.trim());
      if (!mounted || token != _searchToken) return;
      setState(() {
        _searchResults = r;
        _searching = false;
      });
    });
  }

  Future<void> _onSearchResultTap(Map<String, dynamic> item) async {
    _searchDebounce?.cancel();
    _searchToken++;
    FocusScope.of(context).unfocus();
    final title = (item["description"] ?? "Searched area").toString();
    setState(() {
      _searchResults = [];
      _searching = false;
      _searchC.text = title;
    });

    LatLng? p;
    if (item["lat"] is num && item["lng"] is num) {
      p = LatLng((item["lat"] as num).toDouble(), (item["lng"] as num).toDouble());
    } else if (item["place_id"] != null) {
      final d = await _places.getPlaceDetails(item["place_id"].toString());
      final loc = d?["geometry"]?["location"];
      if (loc != null) {
        p = LatLng((loc["lat"] as num).toDouble(), (loc["lng"] as num).toDouble());
      }
    }
    if (p == null || !mounted) return;
    final target = p;

    setState(() {
      _searchMarker = Marker(
        markerId: const MarkerId("search"),
        position: target,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(title: title),
      );
    });
    mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 14));

    // Zones within 3 km of the searched place.
    final near = _zones.where((z) {
      final d = Geolocator.distanceBetween(target.latitude, target.longitude,
          z.center.latitude, z.center.longitude);
      return d <= 3000;
    }).toList();
    final reports = near.fold<int>(0, (s, z) => s + z.count);
    if (near.isNotEmpty) {
      final i = _zones.indexOf(near.first);
      setState(() => _selectedKey = near.first.key);
      if (i >= 0 && _pageController.hasClients) {
        _pageController.animateToPage(i,
            duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(near.isEmpty
          ? "No ${_majorOnly ? "major " : ""}risk zones within 3 km of $title"
          : "$reports report(s) in ${near.length} zone(s) within 3 km"),
    ));
  }

  Widget _summaryBar() {
    final top = _zones.first;
    final reports = _zones.fold<int>(0, (s, z) => s + z.count);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _card.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.insights, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "$reports report(s) in ${_zones.length} "
              "${_majorOnly ? "major " : ""}zone(s) · "
              "Hotspot: ${top.name}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          _levelBadge(top.level),
        ],
      ),
    );
  }

  Widget _levelBadge(_RiskLevel l) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: l.color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: l.color),
        ),
        child: Text(
          l.label,
          style: TextStyle(
              color: l.color, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      );

  Widget _pulseDot(_RiskLevel l, {double size = 10}) {
    return SizedBox(
      width: size * 1.9,
      height: size * 1.9,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) {
          final eased =
              Curves.easeOut.transform((_pulse.value * l.pulseSpeed) % 1.0);
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size + size * 0.9 * eased,
                height: size + size * 0.9 * eased,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: l.color.withValues(alpha: 0.5 * (1 - eased)),
                ),
              ),
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(color: l.color, shape: BoxShape.circle),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _legend() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Risk level",
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 6),
          for (final l in _levels)
            if (!_majorOnly || l != _low)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  _pulseDot(l),
                  const SizedBox(width: 6),
                  Text(
                      "${l.label} · safety ${l.range}",
                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            "${_zones.fold<int>(0, (s, z) => s + z.count)} report(s) shown"
            "${_majorOnly ? " · major only" : ""}",
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }

  String _distanceTo(LatLng p) {
    if (_myPosition == null) return "";
    final d = Geolocator.distanceBetween(
        _myPosition!.latitude, _myPosition!.longitude, p.latitude, p.longitude);
    return d < 1000
        ? "${d.toStringAsFixed(0)} m away"
        : "${(d / 1000).toStringAsFixed(1)} km away";
  }

  Widget _zoneCard(_Zone z, int index) {
    final selected = z.key == _selectedKey;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: EdgeInsets.symmetric(horizontal: 6, vertical: selected ? 0 : 8),
      decoration: BoxDecoration(
        color: _card.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? z.level.color : Colors.white12,
          width: selected ? 2 : 1,
        ),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          _selectZone(z);
          _showZoneDetails(z);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              _pulseDot(z.level, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Text("Zone ${index + 1} of ${_zones.length}",
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11)),
                        const SizedBox(width: 8),
                        _levelBadge(z.level),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      z.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${z.count} report(s) · ${z.topCategories}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    if (_myPosition != null)
                      Text(_distanceTo(z.center),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }

  String _ago(dynamic ts) {
    if (ts is! Timestamp) return "";
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 60) return "${diff.inMinutes} min ago";
    if (diff.inHours < 24) return "${diff.inHours} h ago";
    return "${diff.inDays} day(s) ago";
  }

  void _showZoneDetails(_Zone z) {
    final cats = z.categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final latest = [...z.reports]..sort((a, b) {
        final ta = a["createdAt"], tb = b["createdAt"];
        if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
        return 0;
      });

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
            const SizedBox(height: 16),
            Row(
              children: [
                _pulseDot(z.level, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(z.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ),
                _levelBadge(z.level),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "${z.count} report(s) in this zone"
              "${_myPosition != null ? " · ${_distanceTo(z.center)}" : ""}",
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 18),
            const Text("What is happening here",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            for (final c in cats) _categoryBar(c.key, c.value, z.count),
            const SizedBox(height: 16),
            const Text("Latest reports",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final r in latest.take(5))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: (MyReportsScreen.categoryColors[r["category"]] ??
                          Colors.white)
                      .withValues(alpha: 0.2),
                  child: Icon(
                    MyReportsScreen.categoryIcons[r["category"]] ?? Icons.warning,
                    color: MyReportsScreen.categoryColors[r["category"]] ??
                        Colors.white,
                    size: 20,
                  ),
                ),
                title: Text(
                  (r["category"] ?? "Incident").toString(),
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  [
                    (r["description"] ?? "").toString(),
                    _ago(r["createdAt"]),
                  ].where((s) => s.isNotEmpty).join(" · "),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _bg,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MapScreen(
                      focusLat: z.center.latitude,
                      focusLng: z.center.longitude,
                      focusTitle: z.name,
                      focusSnippet:
                          "${z.count} report(s) · ${z.level.label} risk zone",
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.map),
              label: const Text("Open on Live Map"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryBar(String category, int value, int total) {
    final color = MyReportsScreen.categoryColors[category] ?? Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(MyReportsScreen.categoryIcons[category] ?? Icons.warning,
              color: color, size: 18),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(category,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value / total),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 8,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text("$value",
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
