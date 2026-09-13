import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/places_service.dart';
import '../services/directions_service.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/filter_chips_widget.dart';
import '../widgets/legend_drawer.dart';
import '../widgets/eta_card.dart';
import '../widgets/place_bottom_sheet.dart';
import '../widgets/emergency_sos_sheet.dart';

class MapScreen extends StatefulWidget {
  final double? focusLat;
  final double? focusLng;
  final String? focusTitle;
  final String? focusSnippet;

  const MapScreen({
    super.key,
    this.focusLat,
    this.focusLng,
    this.focusTitle,
    this.focusSnippet,
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

  final TextEditingController searchController = TextEditingController();
  List<dynamic> searchResults = [];
  bool searching = false;

  bool placesLoaded = false;
  List<dynamic> policePlaces = [];
  List<dynamic> hospitalPlaces = [];
  List<dynamic> firePlaces = [];

  double currentZoom = 14;

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
    _loadCustomIcons();
    _listenIncidents();
    getCurrentLocation();
  }

  @override
  void dispose() {
    searchController.dispose();
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
      case "Theft":
        assetPath = "assets/icons/theft.png";
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
        _rebuildIncidentMarkers();
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

      currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
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

    if (currentZoom >= 14) {
      newPlaceMarkers.addAll(
        _markersFromPlaces(policePlaces, policeIcon, "police"),
      );
      newPlaceMarkers.addAll(
        _markersFromPlaces(hospitalPlaces, hospitalIcon, "hospital"),
      );
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
  Future<void> searchLocation(String value) async {
    if (value.isEmpty) {
      setState(() => searchResults = []);
      return;
    }

    setState(() => searching = true);

    final result = await placesService.searchPlaces(value);

    setState(() {
      searchResults = result;
      searching = false;
    });
  }

  Future<void> _onSearchResultTap(Map<String, dynamic> item) async {
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

    if (currentPosition == null) return;

    final response = await directionsService.getDirections(
      originLat: currentPosition!.latitude,
      originLng: currentPosition!.longitude,
      destLat: destinationLat,
      destLng: destinationLng,
    );

    if (response == null) return;

    final route = response["routes"][0];
    final leg = route["legs"][0];

    distanceText = leg["distance"]["text"];
    durationText = leg["duration"]["text"];

    final encodedPolyline = route["overview_polyline"]["points"];

    PolylinePoints polylinePoints = PolylinePoints();
    List<PointLatLng> decoded = polylinePoints.decodePolyline(encodedPolyline);

    List<LatLng> routePoints = [];
    for (var point in decoded) {
      routePoints.add(LatLng(point.latitude, point.longitude));
    }

    polylines.clear();
    polylines.add(
      Polyline(
        polylineId: const PolylineId("route"),
        points: routePoints,
        width: 6,
        color: Colors.blue,
      ),
    );

    if (routePoints.isNotEmpty && mapController != null) {
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

    setState(() {});
  }

  // ===============================
  // In-app navigation (Start / Cancel) — replaces external Google Maps launch
  // ===============================
  void startNavigation() {
    if (destinationLatLng == null) return;

    setState(() => isNavigating = true);

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
      distanceText = "";
      durationText = "";
      destinationLatLng = null;
    });

    _rebuildAllMarkers();
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

  Future<void> _callNumber(String number) async {
    final uri = Uri.parse("tel:$number");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _shareLocation() async {
    if (currentPosition == null) return;

    final link =
        "https://www.google.com/maps?q=${currentPosition!.latitude},${currentPosition!.longitude}";

    await Clipboard.setData(ClipboardData(text: link));

    if (!mounted) return;
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Location link copied — paste it in WhatsApp/SMS to share.",
        ),
      ),
    );
  }

  // ===============================
  // BUILD
  // ===============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xff071B52),
      endDrawer: const LegendDrawer(),

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
                  initialCameraPosition: initialCamera,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  compassEnabled: true,
                  mapToolbarEnabled: true,
                  trafficEnabled: false,
                  buildingsEnabled: true,
                  mapType: MapType.normal,
                  markers: markers,
                  polylines: polylines,
                  onMapCreated: (GoogleMapController controller) async {
                    mapController = controller;

                    try {
                      final style = await rootBundle.loadString(
                        "assets/map_styles/night_style.json",
                      );
                      await controller.setMapStyle(style);
                    } catch (e) {
                      debugPrint("map style error: $e");
                    }

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
                          builder: (_) => Padding(
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
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        );
                      });
                    }
                  },
                  onCameraMove: (position) {
                    final wasVisible = currentZoom >= 14;
                    currentZoom = position.zoom;
                    final isVisible = currentZoom >= 14;
                    if (wasVisible != isVisible) {
                      _rebuildPlaceMarkers();
                    }
                  },
                  onCameraIdle: () {
                    _rebuildIncidentMarkers();
                  },
                ),

                // ===============================
                // Search Bar + Filter Chips
                // ===============================
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
                        onSelected: (filter) {
                          setState(() => selectedFilter = filter);
                          _rebuildIncidentMarkers();
                        },
                      ),
                    ],
                  ),
                ),

                // ===============================
                // ETA Card (with Start / Cancel)
                // ===============================
                Positioned(
                  bottom: 20,
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
                    onPressed: _openEmergencySheet,
                    child: const Icon(Icons.sos, color: Colors.white),
                  ),
                ),
              ],
            ),
    );
  }
}