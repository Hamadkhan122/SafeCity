import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

import '../services/places_service.dart';
import '../services/directions_service.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/filter_chips_widget.dart';
import '../widgets/legend_drawer.dart';
import '../widgets/eta_card.dart';
import '../widgets/place_bottom_sheet.dart';
import '../widgets/emergency_sos_sheet.dart';
import '../widgets/safety_score_card.dart';
import '../models/incident_model.dart';
import '../services/safety_score_service.dart';
import '../services/phone_service.dart';
import '../services/share_service.dart';
import 'sos_screen.dart';

/// One alternative route returned by the Directions API, with its safety
/// score (M5 — Safe Route Suggestion).
class _RouteOption {
  final List<LatLng> points;
  final String distanceText;
  final String durationText;
  final int durationSeconds;
  final String summary;
  RouteSafetyResult safety;

  _RouteOption({
    required this.points,
    required this.distanceText,
    required this.durationText,
    required this.durationSeconds,
    required this.summary,
    required this.safety,
  });
}

class MapScreen extends StatefulWidget {
  final double? focusLat;
  final double? focusLng;
  final String? focusTitle;
  final String? focusSnippet;
  /// true -> draw the route to the focus point straight away (used by the
  /// SOS screen's "Directions" buttons).
  final bool routeToFocus;

  const MapScreen({
    super.key,
    this.focusLat,
    this.focusLng,
    this.focusTitle,
    this.focusSnippet,
    this.routeToFocus = false,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  GoogleMapController? mapController;

  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final PlacesService placesService = PlacesService();
  final DirectionsService directionsService = DirectionsService();

  StreamSubscription<QuerySnapshot>? _incidentSub;
  StreamSubscription<Position>? _navigationSub;

  bool loading = true;
  Position? currentPosition;

  List<QueryDocumentSnapshot> incidentDocs = [];
  String selectedFilter = "All";

  Set<Marker> incidentMarkers = {};
  Set<Marker> placeMarkers = {};
  Marker? meMarker;
  Marker? searchedMarker;
  Marker? focusedMarker;
  Set<Marker> markers = {};

  Set<Polyline> polylines = {};
  String distanceText = "";
  String durationText = "";
  LatLng? destinationLatLng;
  bool isNavigating = false;

  // Navigation mode: every other button is hidden; only "End Navigation"
  // stays. Ending it brings the map back to how it was before the route.
  CameraPosition? _lastCamera; // updated while the map moves
  CameraPosition? _cameraBeforeRoute; // restored after End Navigation

  final TextEditingController searchController = TextEditingController();
  List<dynamic> searchResults = [];
  bool searching = false;

  bool placesLoaded = false;
  List<dynamic> policePlaces = [];
  List<dynamic> hospitalPlaces = [];
  List<dynamic> firePlaces = [];

  double currentZoom = 14;

  // Live traffic layer (Google Maps SDK — free, no extra API).
  bool showTraffic = false;

  // ---- M4 Safety Score / M5 Safe Route ----
  List<IncidentModel> incidents = [];
  SafetyResult? areaSafety;
  List<_RouteOption> routeOptions = [];
  int selectedRouteIndex = 0;

  // ---- Legend highlight (tap an item in the ≡ legend) ----
  static const List<String> _incidentTypes = [
    "Accident", "Fire", "Harassment", "Road Damage", "Fight",
  ];
  String? _highlight;
  List<LatLng> _highlightPoints = [];
  Color _highlightColor = Colors.redAccent;
  Set<Circle> _highlightCircles = {};
  Timer? _highlightTimer;
  bool _cameraMoving = false;
  int _pulseTick = 0;

  BitmapDescriptor? policeIcon;
  BitmapDescriptor? hospitalIcon;
  BitmapDescriptor? fireIcon;

  final Map<String, BitmapDescriptor> _incidentIconCache = {};
  final Map<int, BitmapDescriptor> _clusterIconCache = {};

  static const CameraPosition initialCamera = CameraPosition(
    target: LatLng(33.6844, 73.0479),
    zoom: 14,
  );

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _loadCustomIcons();
    _listenIncidents();
    getCurrentLocation();
  }

  // Dark map style passed straight to GoogleMap(style:) so the map is dark
  // from the first frame (no white flash).
  String? _mapStyle;

  Future<void> _loadMapStyle() async {
    try {
      final style =
          await rootBundle.loadString("assets/map_styles/night_style.json");
      if (mounted) setState(() => _mapStyle = style);
    } catch (e) {
      debugPrint("map style error: $e");
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    searchController.dispose();
    _highlightTimer?.cancel();
    _incidentSub?.cancel();
    _navigationSub?.cancel();
    super.dispose();
  }

  // ===============================
  // Custom marker icons (Police / Hospital / Fire)
  // ===============================
  Future<void> _loadCustomIcons() async {
    policeIcon = await _safeLoadIcon("assets/icons/police.png");
    hospitalIcon = await _safeLoadIcon("assets/icons/hospital.png");
    fireIcon = await _safeLoadIcon("assets/icons/firestation.png");
  }

  Future<BitmapDescriptor> _safeLoadIcon(String path) async {
    try {
      return await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(46, 46)),
        path,
      );
    } catch (e) {
      debugPrint("custom icon load failed ($path): $e");
      return BitmapDescriptor.defaultMarker;
    }
  }

  // ===============================
  // Incident category icon (cached)
  // ===============================
  Future<BitmapDescriptor> getIncidentIcon(String category) async {
    if (_incidentIconCache.containsKey(category)) {
      return _incidentIconCache[category]!;
    }

    String? assetPath;
    switch (category) {
      case "Accident":
        assetPath = "assets/icons/accident.png";
        break;
      case "Fire":
        assetPath = "assets/icons/fire.png";
        break;
      case "Harassment":
        assetPath = "assets/icons/harassment.png";
        break;
      case "Road Damage":
        assetPath = "assets/icons/road_damage.png";
        break;
      case "Fight":
        assetPath = "assets/icons/fight.png";
        break;
    }

    if (assetPath == null) {
      _incidentIconCache[category] = BitmapDescriptor.defaultMarker;
      return BitmapDescriptor.defaultMarker;
    }

    try {
      final icon = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(48, 48)),
        assetPath,
      );
      _incidentIconCache[category] = icon;
      return icon;
    } catch (e) {
      debugPrint("incident icon error ($category): $e");
      _incidentIconCache[category] = BitmapDescriptor.defaultMarker;
      return BitmapDescriptor.defaultMarker;
    }
  }

  // ===============================
  // Realtime Firestore incidents
  // ===============================
  void _listenIncidents() {
    _incidentSub = firestore.collection("reports").snapshots().listen(
      (snapshot) {
        incidentDocs = snapshot.docs;
        incidents = IncidentModel.listFromDocs(snapshot.docs);
        _rebuildIncidentMarkers();
        _recomputeAreaSafety();
        _rescoreRoutes();
      },
      onError: (e) => debugPrint("incident stream error: $e"),
    );
  }

  // ===============================
  // Simple grid-based clustering for incidents
  // ===============================
  double _gridCellSizeForZoom(double zoom) {
    if (zoom >= 17) return 0.0006;
    if (zoom >= 15) return 0.003;
    if (zoom >= 13) return 0.012;
    return 0.05;
  }

  Future<void> _rebuildIncidentMarkers() async {
    final filtered = <Map<String, dynamic>>[];

    for (var doc in incidentDocs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data["latitude"] == null || data["longitude"] == null) continue;
      // AIVE: Suspicious reports (and removed categories) are not shown.
      if (!SafetyScoreService.isPublicReport(data)) continue;
      if (selectedFilter != "All" && data["category"] != selectedFilter) {
        continue;
      }
      filtered.add(data);
    }

    final cellSize = _gridCellSizeForZoom(currentZoom);
    final Map<String, List<Map<String, dynamic>>> buckets = {};

    for (var data in filtered) {
      final lat = (data["latitude"] as num).toDouble();
      final lng = (data["longitude"] as num).toDouble();
      final cellX = (lng / cellSize).floor();
      final cellY = (lat / cellSize).floor();
      final key = "$cellX:$cellY";
      buckets.putIfAbsent(key, () => []).add(data);
    }

    final Set<Marker> newMarkers = {};

    for (var entry in buckets.entries) {
      final group = entry.value;

      if (group.length == 1) {
        final data = group.first;
        final lat = (data["latitude"] as num).toDouble();
        final lng = (data["longitude"] as num).toDouble();
        final icon = await getIncidentIcon(data["category"] ?? "");

        newMarkers.add(
          Marker(
            markerId: MarkerId("incident_${entry.key}"),
            position: LatLng(lat, lng),
            icon: icon,
            infoWindow: InfoWindow(
              title: data["category"],
              snippet: data["description"],
            ),
            onTap: () => _showLocationSheet(
              LatLng(lat, lng),
              (data["category"] ?? "Incident").toString(),
              (data["description"] ?? data["address"] ?? "").toString(),
            ),
          ),
        );
      } else {
        double avgLat = 0;
        double avgLng = 0;
        for (var data in group) {
          avgLat += (data["latitude"] as num).toDouble();
          avgLng += (data["longitude"] as num).toDouble();
        }
        avgLat /= group.length;
        avgLng /= group.length;

        final clusterTarget = LatLng(avgLat, avgLng);
        final clusterIcon = await _createClusterIcon(group.length);

        newMarkers.add(
          Marker(
            markerId: MarkerId("cluster_${entry.key}"),
            position: clusterTarget,
            icon: clusterIcon,
            onTap: () => moveCamera(clusterTarget, currentZoom + 2),
          ),
        );
      }
    }

    incidentMarkers = newMarkers;
    _rebuildAllMarkers();
  }

  Future<BitmapDescriptor> _createClusterIcon(int count) async {
    final cacheKey = count > 99 ? 100 : count;

    if (_clusterIconCache.containsKey(cacheKey)) {
      return _clusterIconCache[cacheKey]!;
    }

    const double size = 120;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));

    final fillPaint = Paint()..color = const Color(0xffE53935);
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2, fillPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size / 2 - 3,
      borderPaint,
    );

    final label = count > 99 ? "99+" : count.toString();
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 36,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
    );

    final image = await recorder
        .endRecording()
        .toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    final descriptor = BitmapDescriptor.fromBytes(bytes);
    _clusterIconCache[cacheKey] = descriptor;
    return descriptor;
  }

  // ===============================
  // Marker set assembly
  // ===============================
  void _rebuildAllMarkers() {
    final combined = <Marker>{};
    combined.addAll(incidentMarkers);
    combined.addAll(placeMarkers);
    if (meMarker != null) combined.add(meMarker!);
    if (searchedMarker != null) combined.add(searchedMarker!);
    if (focusedMarker != null) combined.add(focusedMarker!);

    if (!mounted) return;
    setState(() {
      markers = combined;
    });
  }

  // ===============================
  // Camera helper
  // ===============================
  void moveCamera(LatLng target, double zoom) {
    if (mapController == null) return;
    mapController!.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
  }

  // ===============================
  // getCurrentLocation
  // ===============================
  Future<void> getCurrentLocation() async {
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) return;
      if (permission == LocationPermission.deniedForever) return;

      // FAST START: show the map immediately at the phone's last known
      // location, then refine with a fresh high-accuracy GPS fix below.
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && currentPosition == null) {
          currentPosition = last;
          meMarker = Marker(
            markerId: const MarkerId("me"),
            position: LatLng(last.latitude, last.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
            infoWindow: const InfoWindow(title: "You are here"),
          );
          _rebuildAllMarkers();
          _recomputeAreaSafety();
          if (mounted) setState(() => loading = false);
          moveCamera(LatLng(last.latitude, last.longitude), 16);
        }
      } catch (_) {}

      currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      meMarker = Marker(
        markerId: const MarkerId("me"),
        position: LatLng(
          currentPosition!.latitude,
          currentPosition!.longitude,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueAzure,
        ),
        infoWindow: const InfoWindow(title: "You are here"),
      );

      _rebuildAllMarkers();
      _recomputeAreaSafety();

      moveCamera(
        LatLng(currentPosition!.latitude, currentPosition!.longitude),
        16,
      );
    } catch (e) {
      debugPrint("getCurrentLocation error: $e");
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }

    await loadNearbyPlaces();
  }

  // ===============================
  // Nearby Places (zoom-gated visibility)
  // ===============================
  Future<void> loadNearbyPlaces() async {
    if (currentPosition == null) return;
    if (placesLoaded) return;
    placesLoaded = true;

    try {
      policePlaces = await placesService.nearbyPlaces(
        latitude: currentPosition!.latitude,
        longitude: currentPosition!.longitude,
        type: "police",
      );
      hospitalPlaces = await placesService.nearbyPlaces(
        latitude: currentPosition!.latitude,
        longitude: currentPosition!.longitude,
        type: "hospital",
      );
      firePlaces = await placesService.nearbyPlaces(
        latitude: currentPosition!.latitude,
        longitude: currentPosition!.longitude,
        type: "fire_station",
      );

      _rebuildPlaceMarkers();
    } catch (e) {
      debugPrint("loadNearbyPlaces error: $e");
    }
  }

  void _rebuildPlaceMarkers() {
    final Set<Marker> newPlaceMarkers = {};

    final showAll = currentZoom >= 14;
    if (showAll || _highlight == "Police Station") {
      newPlaceMarkers.addAll(
        _markersFromPlaces(policePlaces, policeIcon, "police"),
      );
    }
    if (showAll || _highlight == "Hospital") {
      newPlaceMarkers.addAll(
        _markersFromPlaces(hospitalPlaces, hospitalIcon, "hospital"),
      );
    }
    if (showAll || _highlight == "Fire Station") {
      newPlaceMarkers.addAll(
        _markersFromPlaces(firePlaces, fireIcon, "fire"),
      );
    }

    placeMarkers = newPlaceMarkers;
    _rebuildAllMarkers();
  }

  Set<Marker> _markersFromPlaces(
    List<dynamic> places,
    BitmapDescriptor? icon,
    String prefix,
  ) {
    final Set<Marker> result = {};

    for (var place in places) {
      final lat = (place["geometry"]["location"]["lat"] as num).toDouble();
      final lng = (place["geometry"]["location"]["lng"] as num).toDouble();
      final placeId = place["place_id"] ?? "${prefix}_$lat$lng";

      result.add(
        Marker(
          markerId: MarkerId("${prefix}_$placeId"),
          position: LatLng(lat, lng),
          icon: icon ?? BitmapDescriptor.defaultMarker,
          onTap: () => _onPlaceMarkerTap(place),
        ),
      );
    }

    return result;
  }

  void _onPlaceMarkerTap(dynamic place) {
    final placeId = place["place_id"];
    if (placeId == null) return;
    _selectPlace(placeId);
  }

  // ===============================
  // Search
  // ===============================
  // Debounce + "latest request wins": typing fast no longer shows old
  // results, and a result tap is never overwritten by a late answer.
  Timer? _searchDebounce;
  int _searchToken = 0;

  Future<void> searchLocation(String value) async {
    _searchDebounce?.cancel();
    final token = ++_searchToken;
    if (value.trim().length < 2) {
      setState(() {
        searchResults = [];
        searching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted || token != _searchToken) return;
      setState(() => searching = true);
      final result = await placesService.searchPlaces(value.trim());
      if (!mounted || token != _searchToken) return;
      setState(() {
        searchResults = result;
        searching = false;
      });
    });
  }

  Future<void> _onSearchResultTap(Map<String, dynamic> item) async {
    _searchDebounce?.cancel();
    _searchToken++; // ignore any answer still on its way
    searching = false;
    // Free-search result (no place_id): just drop a pin and show the sheet.
    if (item["lat"] is num && item["lng"] is num) {
      final p = LatLng(
          (item["lat"] as num).toDouble(), (item["lng"] as num).toDouble());
      final title = (item["description"] ?? "Searched location").toString();
      searchController.clear();
      FocusScope.of(context).unfocus();
      setState(() => searchResults = []);
      searchedMarker = Marker(
        markerId: const MarkerId("searched"),
        position: p,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(title: title),
      );
      _rebuildAllMarkers();
      moveCamera(p, 16);
      _showLocationSheet(p, title, "");
      return;
    }

    final placeId = item["place_id"] ?? "";
    searchController.clear();
    setState(() => searchResults = []);

    if (placeId.isEmpty) return;

    await _selectPlace(placeId);
  }

  // ===============================
  // Unified place selection (search result OR marker tap)
  // ===============================
  Future<void> _selectPlace(String placeId) async {
    final place = await placesService.getPlaceDetails(placeId);
    if (place == null) return;

    final lat = (place["geometry"]["location"]["lat"] as num).toDouble();
    final lng = (place["geometry"]["location"]["lng"] as num).toDouble();

    searchedMarker = Marker(
      markerId: const MarkerId("searched"),
      position: LatLng(lat, lng),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      infoWindow: InfoWindow(
        title: place["name"] ?? "",
        snippet: place["formatted_address"] ?? "",
      ),
    );

    _rebuildAllMarkers();
    moveCamera(LatLng(lat, lng), 17);

    if (currentPosition != null) {
      await getDirections(destinationLat: lat, destinationLng: lng);
    }

    if (!mounted) return;

    final phone = place["formatted_phone_number"];

    await showPlaceDetailsSheet(
      context: context,
      place: place,
      distanceText: distanceText,
      durationText: durationText,
      onNavigate: startNavigation,
      onCall: phone != null ? () => _callNumber(phone) : null,
    );
  }

  // ===============================
  // Directions
  // ===============================
  Future<void> getDirections({
    required double destinationLat,
    required double destinationLng,
  }) async {
    destinationLatLng = LatLng(destinationLat, destinationLng);
    if (routeOptions.isEmpty && !isNavigating) {
      _cameraBeforeRoute = _lastCamera; // map state before the route
    }

    if (currentPosition == null) {
      _mapSnack("Your location isn't available yet — try again in a moment");
      return;
    }

    Map<String, dynamic>? response;
    try {
      response = await directionsService.getDirections(
        originLat: currentPosition!.latitude,
        originLng: currentPosition!.longitude,
        destLat: destinationLat,
        destLng: destinationLng,
        alternatives: true, // M5: get all candidate routes
        // M5: serious incidents on the way -> extra routes around them
        avoid: SafetyScoreService.hotspotsBetween(
          oLat: currentPosition!.latitude,
          oLng: currentPosition!.longitude,
          dLat: destinationLat,
          dLng: destinationLng,
          incidents: incidents,
        ),
      );
      // Fallback: some requests fail with alternatives -> try single route.
      response ??= await directionsService.getDirections(
        originLat: currentPosition!.latitude,
        originLng: currentPosition!.longitude,
        destLat: destinationLat,
        destLng: destinationLng,
      );
    } catch (e) {
      debugPrint("getDirections error: $e");
    }

    if (response == null) {
      _mapSnack("Couldn't get directions. Check your internet and try again.");
      return;
    }

    // ---- Build + score every alternative route ----
    final options = <_RouteOption>[];
    final polylinePoints = PolylinePoints();

    for (final route in response["routes"]) {
      final leg = route["legs"][0];
      final decoded =
          polylinePoints.decodePolyline(route["overview_polyline"]["points"]);
      final pts = decoded.map((p) => LatLng(p.latitude, p.longitude)).toList();

      options.add(
        _RouteOption(
          points: pts,
          distanceText: leg["distance"]["text"],
          durationText: leg["duration"]["text"],
          durationSeconds: (leg["duration"]["value"] as num?)?.toInt() ?? 0,
          summary: (route["summary"] ?? "").toString(),
          safety: SafetyScoreService.scoreRoute(
            points: pts.map((p) => [p.latitude, p.longitude]).toList(),
            incidents: incidents,
          ),
        ),
      );
    }

    if (options.isEmpty) return;

    routeOptions = options;
    selectedRouteIndex = _safestRouteIndex();
    _drawRoutes();

    if (mapController != null) {
      final swLat = currentPosition!.latitude < destinationLat
          ? currentPosition!.latitude
          : destinationLat;
      final swLng = currentPosition!.longitude < destinationLng
          ? currentPosition!.longitude
          : destinationLng;
      final neLat = currentPosition!.latitude > destinationLat
          ? currentPosition!.latitude
          : destinationLat;
      final neLng = currentPosition!.longitude > destinationLng
          ? currentPosition!.longitude
          : destinationLng;

      final bounds = LatLngBounds(
        southwest: LatLng(swLat, swLng),
        northeast: LatLng(neLat, neLng),
      );

      mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    }

    if (routeOptions.length > 1 && mounted) {
      final best = routeOptions[selectedRouteIndex];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // Floating above the ETA card so it never covers Cancel/Start.
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(15, 0, 15, 230),
          duration: const Duration(seconds: 3),
          content: Text(
            "${selectedRouteIndex == _fastestRouteIndex() ? "Fastest route is also safe enough" : "Safer route selected"} "
            "(safety ${best.safety.score}/100). Tap a grey route to switch.",
          ),
        ),
      );
    }
  }

  void _mapSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Tap anywhere on the map (or on an incident) -> sheet with distance,
  /// "Get directions" (route + distance/ETA card).
  void _onMapTap(LatLng p) {
    if (searchResults.isNotEmpty) {
      setState(() => searchResults = []);
      FocusScope.of(context).unfocus();
      return;
    }
    if (isNavigating) return;

    searchedMarker = Marker(
      markerId: const MarkerId("searched"),
      position: p,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
      infoWindow: const InfoWindow(title: "Selected location"),
    );
    _rebuildAllMarkers();
    _showLocationSheet(
      p,
      "Selected location",
      "${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}",
    );
  }

  void _showLocationSheet(LatLng p, String title, String subtitle) {
    String distance = "";
    if (currentPosition != null) {
      final d = Geolocator.distanceBetween(
        currentPosition!.latitude,
        currentPosition!.longitude,
        p.latitude,
        p.longitude,
      );
      distance = d < 1000
          ? "${d.toStringAsFixed(0)} m away (straight line)"
          : "${(d / 1000).toStringAsFixed(1)} km away (straight line)";
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                height: 5,
                width: 60,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(subtitle, style: const TextStyle(color: Colors.black87)),
            ],
            if (distance.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.straighten, size: 18, color: Colors.blue),
                  const SizedBox(width: 6),
                  Text(distance, style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff0A2E73),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      getDirections(
                        destinationLat: p.latitude,
                        destinationLng: p.longitude,
                      );
                    },
                    icon: const Icon(Icons.directions),
                    label: const Text("Get directions"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Draws the route to [target] as soon as the user's location is known
  /// (waits up to ~10 s on a cold start).
  Future<void> _routeToFocusWhenReady(LatLng target) async {
    for (int i = 0; i < 20 && currentPosition == null; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
    }
    if (currentPosition == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Waiting for your location — try again")),
        );
      }
      return;
    }
    await getDirections(
      destinationLat: target.latitude,
      destinationLng: target.longitude,
    );
  }

  // ===============================
  // M4 — Safety Score helpers
  // ===============================
  void _recomputeAreaSafety() {
    if (currentPosition == null) return;
    final result = SafetyScoreService.scoreAt(
      lat: currentPosition!.latitude,
      lng: currentPosition!.longitude,
      incidents: incidents,
    );
    if (mounted) setState(() => areaSafety = result);
  }

  // ===============================
  // M5 — Safe Route helpers
  // ===============================
  /// UC-09 BR-1 / FR-SR-01: the safer route is preferred over the
  /// fastest one only when the safety difference is significant
  /// (>= [significantSafetyGain] points) AND the detour is reasonable
  /// (at most 50 % or 10 minutes longer than the fastest route).
  // Small category points (Fire 3, Accident 3, others 2) give small score
  // differences: one incident near a route already makes it ~2 points worse.
  static const int significantSafetyGain = 2;
  static const double maxDetourFactor = 1.5;
  static const int maxDetourExtraSeconds = 600;

  int _fastestRouteIndex() {
    int f = 0;
    for (int i = 1; i < routeOptions.length; i++) {
      final d = routeOptions[i].durationSeconds;
      if (d > 0 && d < routeOptions[f].durationSeconds) f = i;
    }
    return f;
  }

  bool _detourOk(int i, int fastest) {
    final base = routeOptions[fastest].durationSeconds;
    final d = routeOptions[i].durationSeconds;
    if (base <= 0 || d <= 0) return true; // unknown durations
    final limit = (base * maxDetourFactor) > (base + maxDetourExtraSeconds)
        ? base * maxDetourFactor
        : (base + maxDetourExtraSeconds).toDouble();
    return d <= limit;
  }

  int _safestRouteIndex() {
    final fastest = _fastestRouteIndex();
    int best = fastest;
    for (int i = 0; i < routeOptions.length; i++) {
      if (!_detourOk(i, fastest)) continue;
      final s = routeOptions[i].safety.score;
      final b = routeOptions[best].safety.score;
      // Safer wins; on equal safety the shorter one wins.
      if (s > b ||
          (s == b &&
              routeOptions[i].durationSeconds <
                  routeOptions[best].durationSeconds)) {
        best = i;
      }
    }
    final gain =
        routeOptions[best].safety.score - routeOptions[fastest].safety.score;
    return gain >= significantSafetyGain ? best : fastest;
  }

  /// FR-SR-04: re-score routes whenever incident data changes and switch
  /// only when the new route gives a meaningful improvement (BR-03).
  void _rescoreRoutes() {
    if (routeOptions.isEmpty) return;
    for (final r in routeOptions) {
      r.safety = SafetyScoreService.scoreRoute(
        points: r.points.map((p) => [p.latitude, p.longitude]).toList(),
        incidents: incidents,
      );
    }

    final candidate = _safestRouteIndex();
    final gain = routeOptions[candidate].safety.score -
        routeOptions[selectedRouteIndex].safety.score;

    if (candidate != selectedRouteIndex && gain >= significantSafetyGain) {
      selectedRouteIndex = candidate;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.fromLTRB(15, 0, 15, 230),
            content: Text(
              "New verified incident on your route — switched to a safer route.",
            ),
          ),
        );
      }
    }
    _drawRoutes();
  }

  Color _routeColor(SafetyLevel level) {
    switch (level) {
      case SafetyLevel.safe:
        return Colors.greenAccent.shade400;
      case SafetyLevel.moderate:
        return Colors.amber;
      case SafetyLevel.unsafe:
        return Colors.redAccent;
    }
  }

  void _drawRoutes() {
    final selected = routeOptions[selectedRouteIndex];
    distanceText = selected.distanceText;
    durationText = selected.durationText;

    final newPolylines = <Polyline>{};
    for (int i = 0; i < routeOptions.length; i++) {
      final r = routeOptions[i];
      final isSelected = i == selectedRouteIndex;
      newPolylines.add(
        Polyline(
          polylineId: PolylineId("route_$i"),
          points: r.points,
          width: isSelected ? 7 : 5,
          color: isSelected
              ? _routeColor(r.safety.level)
              : Colors.grey.withValues(alpha: 0.7),
          zIndex: isSelected ? 2 : 1,
          consumeTapEvents: true,
          onTap: () {
            if (isNavigating) return;
            setState(() => selectedRouteIndex = i);
            _drawRoutes();
          },
        ),
      );
    }

    if (mounted) {
      setState(() {
        polylines
          ..clear()
          ..addAll(newPolylines);
      });
    }
  }

  // ===============================
  // In-app navigation (Start / Cancel) — replaces external Google Maps launch
  // ===============================
  void startNavigation() {
    if (destinationLatLng == null) return;

    // Clean navigation view: close search results / legend highlight.
    FocusScope.of(context).unfocus();
    setState(() {
      isNavigating = true;
      searchResults = [];
    });

    _navigationSub?.cancel();
    _navigationSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((position) {
          currentPosition = position;

          meMarker = Marker(
            markerId: const MarkerId("me"),
            position: LatLng(position.latitude, position.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
            infoWindow: const InfoWindow(title: "You are here"),
          );

          _rebuildAllMarkers();
          _recomputeAreaSafety();
          moveCamera(LatLng(position.latitude, position.longitude), 17);
        });
  }

  void cancelNavigation() {
    _navigationSub?.cancel();
    _navigationSub = null;

    searchedMarker = null;

    setState(() {
      isNavigating = false;
      polylines.clear();
      routeOptions = [];
      selectedRouteIndex = 0;
      distanceText = "";
      durationText = "";
      destinationLatLng = null;
    });

    _rebuildAllMarkers();

    // Back to the map view the user had before the route was drawn.
    final before = _cameraBeforeRoute;
    _cameraBeforeRoute = null;
    if (before != null) {
      mapController?.animateCamera(CameraUpdate.newCameraPosition(before));
    } else if (currentPosition != null) {
      moveCamera(
          LatLng(currentPosition!.latitude, currentPosition!.longitude), 16);
    }
  }

  // ===============================
  // Emergency SOS
  // ===============================
  Map<String, dynamic>? _nearest(List<dynamic> places) {
    if (currentPosition == null || places.isEmpty) return null;

    Map<String, dynamic>? nearest;
    double bestDistance = double.infinity;

    for (var place in places) {
      final lat = (place["geometry"]["location"]["lat"] as num).toDouble();
      final lng = (place["geometry"]["location"]["lng"] as num).toDouble();
      final distance = Geolocator.distanceBetween(
        currentPosition!.latitude,
        currentPosition!.longitude,
        lat,
        lng,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = place;
      }
    }

    return nearest;
  }

  // Old in-map emergency sheet — kept for reference; the SOS button now
  // opens the full Emergency SOS screen.
  // ignore: unused_element
  void _openEmergencySheet() {
    showEmergencySosSheet(
      context: context,
      nearestPolice: _nearest(policePlaces),
      nearestHospital: _nearest(hospitalPlaces),
      nearestFire: _nearest(firePlaces),
      onNavigateTo: (place) async {
        Navigator.pop(context);
        final lat = (place["geometry"]["location"]["lat"] as num).toDouble();
        final lng = (place["geometry"]["location"]["lng"] as num).toDouble();
        moveCamera(LatLng(lat, lng), 17);
        await getDirections(destinationLat: lat, destinationLng: lng);
      },
      onCall: _callNumber,
      onShareLocation: _shareLocation,
    );
  }

  // Direct call -> returns to the app when the call ends (dialer fallback).
  Future<void> _callNumber(String number) async {
    await PhoneService.call(context, number);
  }

  Future<void> _shareLocation() async {
    if (currentPosition == null) return;

    if (!mounted) return;
    Navigator.pop(context);

    // Android share sheet: WhatsApp, SMS, Gmail... (copies if unavailable)
    await ShareService.shareText(
      context,
      ShareService.locationMessage(
        currentPosition!.latitude,
        currentPosition!.longitude,
      ),
      title: "Share your location via",
    );
  }

  // ===============================
  // Legend highlight — tap an item in the ≡ legend drawer
  // ===============================
  Map<String, int> get _legendCounts {
    final counts = <String, int>{
      "Police Station": policePlaces.length,
      "Hospital": hospitalPlaces.length,
      "Fire Station": firePlaces.length,
    };
    for (final t in _incidentTypes) {
      counts[t] = incidents
          .where((i) =>
              i.category == t && SafetyScoreService.isPublicStatus(i.status))
          .length;
    }
    return counts;
  }

  Color _colorFor(String item) {
    switch (item) {
      case "Police Station":
        return Colors.lightBlueAccent;
      case "Hospital":
        return Colors.pinkAccent;
      case "Fire Station":
        return Colors.orangeAccent;
      case "Accident":
        return Colors.redAccent;
      case "Fire":
        return Colors.deepOrangeAccent;
      case "Road Damage":
        return Colors.amber;
      case "Fight":
        return Colors.orange;
      case "Harassment":
        return Colors.pinkAccent;
    }
    return Colors.redAccent;
  }

  List<LatLng> _pointsFor(String item) {
    List<dynamic>? places;
    if (item == "Police Station") places = policePlaces;
    if (item == "Hospital") places = hospitalPlaces;
    if (item == "Fire Station") places = firePlaces;
    if (places != null) {
      return places
          .map((p) => LatLng(
                (p["geometry"]["location"]["lat"] as num).toDouble(),
                (p["geometry"]["location"]["lng"] as num).toDouble(),
              ))
          .toList();
    }
    return incidents
        .where((i) =>
            i.category == item && SafetyScoreService.isPublicStatus(i.status))
        .map((i) => LatLng(i.latitude, i.longitude))
        .toList();
  }

  void _onLegendSelect(String item) {
    _scaffoldKey.currentState?.closeEndDrawer();

    final points = _pointsFor(item);
    if (points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No $item found nearby")),
      );
      return;
    }

    setState(() {
      _highlight = item;
      _highlightPoints = points;
      _highlightColor = _colorFor(item);
      // Incident types also filter the incident markers.
      selectedFilter = _incidentTypes.contains(item) ? item : "All";
    });
    _rebuildIncidentMarkers();
    _rebuildPlaceMarkers();
    _fitToPoints(points);

    _highlightTimer?.cancel();
    _highlightTimer = Timer.periodic(
      const Duration(milliseconds: 140),
      (_) => _updateHighlightCircles(),
    );
    _updateHighlightCircles(force: true);
  }

  void _clearHighlight() {
    _highlightTimer?.cancel();
    setState(() {
      _highlight = null;
      _highlightPoints = [];
      _highlightCircles = {};
      selectedFilter = "All";
    });
    _rebuildIncidentMarkers();
    _rebuildPlaceMarkers();
  }

  void _fitToPoints(List<LatLng> points) {
    if (mapController == null || points.isEmpty) return;
    if (points.length == 1) {
      mapController!.animateCamera(CameraUpdate.newLatLngZoom(points.first, 16));
      return;
    }
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - 0.002, minLng - 0.002),
          northeast: LatLng(maxLat + 0.002, maxLng + 0.002),
        ),
        90,
      ),
    );
  }

  /// Pulsing rings around every highlighted place. Paused while the user
  /// is dragging/zooming so the map never feels stuck.
  void _updateHighlightCircles({bool force = false}) {
    if (!mounted || _highlight == null) return;
    if (_cameraMoving && !force) return;

    _pulseTick = (_pulseTick + 1) % 14;
    final t = Curves.easeOut.transform(_pulseTick / 14);
    // Keep rings visible at any zoom level.
    final base = 60 * math.pow(2, 16 - currentZoom.clamp(10, 19)).toDouble();

    final circles = <Circle>{};
    for (int i = 0; i < _highlightPoints.length; i++) {
      final p = _highlightPoints[i];
      circles.add(Circle(
        circleId: CircleId("hl_core_$i"),
        center: p,
        radius: base * 0.6,
        fillColor: _highlightColor.withValues(alpha: 0.45),
        strokeColor: Colors.white,
        strokeWidth: 2,
        zIndex: 3,
      ));
      circles.add(Circle(
        circleId: CircleId("hl_ring_$i"),
        center: p,
        radius: base * (0.6 + 1.6 * t),
        fillColor: _highlightColor.withValues(alpha: 0.30 * (1 - t)),
        strokeColor: _highlightColor.withValues(alpha: 0.8 * (1 - t)),
        strokeWidth: 2,
        zIndex: 2,
      ));
    }
    setState(() => _highlightCircles = circles);
  }

  // ===============================
  // BUILD
  // ===============================
  /// Bottom bar shown while navigating: distance, ETA, End Navigation.
  Widget _navigationBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black26)],
      ),
      child: Row(
        children: [
          const Icon(Icons.navigation, color: Colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(durationText,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                Text(distanceText,
                    style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: cancelNavigation,
            icon: const Icon(Icons.close),
            label: const Text("End Navigation",
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xff071B52),
      endDrawer: LegendDrawer(
        onSelect: _onLegendSelect,
        selected: _highlight,
        counts: _legendCounts,
      ),

      appBar: AppBar(
        backgroundColor: const Color(0xff071B52),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Live Map",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),

      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : Stack(
              children: [
                // ===============================
                // Google Map
                // ===============================
                GoogleMap(
                  initialCameraPosition: currentPosition != null
                      ? CameraPosition(
                          target: LatLng(
                            currentPosition!.latitude,
                            currentPosition!.longitude,
                          ),
                          zoom: 16,
                        )
                      : initialCamera,
                  style: _mapStyle,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  compassEnabled: true,
                  mapToolbarEnabled: true,
                  trafficEnabled: showTraffic,
                  buildingsEnabled: true,
                  mapType: MapType.normal,
                  markers: markers,
                  polylines: polylines,
                  circles: _highlightCircles,
                  onCameraMoveStarted: () => _cameraMoving = true,
                  onMapCreated: (GoogleMapController controller) async {
                    mapController = controller;

                    if (currentPosition != null) {
                      moveCamera(
                        LatLng(
                          currentPosition!.latitude,
                          currentPosition!.longitude,
                        ),
                        16,
                      );
                    }

                    if (widget.focusLat != null && widget.focusLng != null) {
                      final focusTarget = LatLng(
                        widget.focusLat!,
                        widget.focusLng!,
                      );

                      focusedMarker = Marker(
                        markerId: const MarkerId("focused"),
                        position: focusTarget,
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueRose,
                        ),
                        infoWindow: InfoWindow(
                          title: widget.focusTitle ?? "Incident",
                          snippet: widget.focusSnippet ?? "",
                        ),
                      );
                      _rebuildAllMarkers();
                      moveCamera(focusTarget, 17);

                      if (widget.routeToFocus) {
                        _routeToFocusWhenReady(focusTarget);
                        return;
                      }

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        showModalBottomSheet<void>(
                          context: context,
                          backgroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(28),
                            ),
                          ),
                          builder: (sheetContext) => Padding(
                            padding: const EdgeInsets.all(22),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Center(
                                  child: Container(
                                    height: 5,
                                    width: 60,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade400,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  widget.focusTitle ?? "Incident",
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  widget.focusSnippet ?? "",
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xff0A2E73),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: () {
                                      Navigator.pop(sheetContext);
                                      _routeToFocusWhenReady(focusTarget);
                                    },
                                    icon: const Icon(Icons.directions),
                                    label: const Text("Get directions"),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        );
                      });
                    }
                  },
                  onCameraMove: (position) {
                    _lastCamera = position;
                    final wasVisible = currentZoom >= 14;
                    currentZoom = position.zoom;
                    final isVisible = currentZoom >= 14;
                    if (wasVisible != isVisible) {
                      _rebuildPlaceMarkers();
                    }
                  },
                  onCameraIdle: () {
                    _cameraMoving = false;
                    _rebuildIncidentMarkers();
                  },
                  onTap: _onMapTap, // select any area -> directions/distance
                ),

                // ===============================
                // Safety Score card (M4) / Route safety (M5)
                // Placed before the search bar so search results overlay it.
                // ===============================
                if (isNavigating)
                  const SizedBox.shrink()
                else if (routeOptions.isNotEmpty)
                  Positioned(
                    top: 130,
                    left: 15,
                    right: 15,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SafetyScoreCard(
                        title: "Route Safety",
                        score: routeOptions[selectedRouteIndex].safety.score,
                        level: routeOptions[selectedRouteIndex].safety.level,
                        subtitle:
                            "${routeOptions[selectedRouteIndex].safety.incidentsNearRoute} incident(s) near route"
                            "${routeOptions.length > 1 ? " · ${selectedRouteIndex + 1}/${routeOptions.length} routes" : ""}",
                      ),
                    ),
                  )
                else if (areaSafety != null)
                  Positioned(
                    top: 130,
                    left: 15,
                    right: 15,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SafetyScoreCard(
                        title: "Area Safety",
                        score: areaSafety!.score,
                        level: areaSafety!.level,
                        subtitle:
                            "${areaSafety!.incidentCount} incident(s) within 1 km of you",
                        onTap: () => showSafetyDetailsSheet(
                          context: context,
                          title: "Safety around you",
                          result: areaSafety!,
                        ),
                      ),
                    ),
                  ),

                // ===============================
                // Legend highlight banner
                // ===============================
                if (_highlight != null && !isNavigating)
                  Positioned(
                    top: 200,
                    left: 15,
                    right: 15,
                    child: Material(
                      color: const Color(0xff0E2A6B),
                      elevation: 6,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                        child: Row(
                          children: [
                            Icon(Icons.radar, color: _highlightColor),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "Showing ${_highlightPoints.length} $_highlight"
                                "${_highlightPoints.length == 1 ? "" : " locations"}",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => _fitToPoints(_highlightPoints),
                              child: const Text("Zoom"),
                            ),
                            IconButton(
                              tooltip: "Clear",
                              onPressed: _clearHighlight,
                              icon: const Icon(Icons.close, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ===============================
                // Search Bar + Filter Chips (hidden while navigating)
                // ===============================
                if (!isNavigating)
                Positioned(
                  top: 20,
                  left: 15,
                  right: 15,
                  child: Column(
                    children: [
                      SearchBarWidget(
                        controller: searchController,
                        onChanged: searchLocation,
                        results: searchResults,
                        searching: searching,
                        onResultTap: _onSearchResultTap,
                      ),
                      const SizedBox(height: 10),
                      FilterChipsWidget(
                        selectedFilter: selectedFilter,
                        counts: _legendCounts,
                        onSelected: (filter) {
                          if (_highlight != null) {
                            _highlightTimer?.cancel();
                            _highlight = null;
                            _highlightPoints = [];
                            _highlightCircles = {};
                          }
                          setState(() => selectedFilter = filter);
                          _rebuildIncidentMarkers();
                          _rebuildPlaceMarkers();
                        },
                      ),
                    ],
                  ),
                ),

                // ===============================
                // Navigation mode: only the trip info + End Navigation
                // ===============================
                if (isNavigating)
                  Positioned(
                    bottom: 24,
                    left: 15,
                    right: 15,
                    child: _navigationBar(),
                  )
                else ...[
                // ===============================
                // ETA Card (with Start / Cancel)
                // ===============================
                Positioned(
                  bottom: 28,
                  left: 15,
                  right: 90,
                  child: EtaCard(
                    distanceText: distanceText,
                    durationText: durationText,
                    isNavigating: isNavigating,
                    onStart: startNavigation,
                    onCancel: cancelNavigation,
                  ),
                ),

                // ===============================
                // My Location FAB
                // ===============================
                Positioned(
                  bottom: 20,
                  right: 15,
                  child: FloatingActionButton(
                    heroTag: "myLocation",
                    backgroundColor: const Color(0xff0A2E73),
                    onPressed: () {
                      if (currentPosition == null) return;
                      moveCamera(
                        LatLng(
                          currentPosition!.latitude,
                          currentPosition!.longitude,
                        ),
                        17,
                      );
                    },
                    child: const Icon(Icons.my_location, color: Colors.white),
                  ),
                ),

                // ===============================
                // Traffic toggle FAB (bottom-left)
                // ===============================
                Positioned(
                  bottom: 20,
                  left: 15,
                  child: FloatingActionButton.extended(
                    heroTag: "traffic",
                    backgroundColor:
                        showTraffic ? const Color(0xffD32F2F) : Colors.white,
                    foregroundColor:
                        showTraffic ? Colors.white : const Color(0xff0A2E73),
                    onPressed: () => setState(() => showTraffic = !showTraffic),
                    icon: const Icon(Icons.traffic),
                    label: Text(showTraffic ? "Traffic on" : "Traffic"),
                  ),
                ),

                // ===============================
                // Refresh Nearby Places FAB
                // ===============================
                Positioned(
                  bottom: 90,
                  right: 15,
                  child: FloatingActionButton(
                    heroTag: "refresh",
                    backgroundColor: Colors.green,
                    onPressed: () {
                      placesLoaded = false;
                      loadNearbyPlaces();
                    },
                    child: const Icon(Icons.refresh),
                  ),
                ),

                // ===============================
                // Legend Drawer FAB
                // ===============================
                Positioned(
                  bottom: 160,
                  right: 15,
                  child: FloatingActionButton(
                    heroTag: "legend",
                    backgroundColor: Colors.white,
                    onPressed: () =>
                        _scaffoldKey.currentState?.openEndDrawer(),
                    child: const Icon(Icons.layers, color: Color(0xff0A2E73)),
                  ),
                ),

                // ===============================
                // Emergency SOS FAB
                // ===============================
                Positioned(
                  bottom: 230,
                  right: 15,
                  child: FloatingActionButton(
                    heroTag: "sos",
                    backgroundColor: Colors.red,
                    // Same Emergency SOS screen as Home (helplines, nearest
                    // help, SOS to contact, share location).
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SosScreen()),
                    ),
                    child: const Icon(Icons.sos, color: Colors.white),
                  ),
                ),
                ],
              ],
            ),
    );
  }
}