import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'login_screen.dart';
import 'map_screen.dart';
import 'report_screen.dart';
import 'profile_screen.dart';
import 'sos_screen.dart';
import 'heatmap_screen.dart';
import 'notification_screen.dart';
import 'my_reports_screen.dart';
import 'incident_history_screen.dart';
import 'safetyscore_screen.dart';
import '../services/safety_score_service.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../widgets/notification_badge.dart';
import '../widgets/notification_banner.dart';
import '../widgets/sos_chat_banner.dart';
import '../services/settings_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final NotificationService notificationService = NotificationService();

  int currentIndex = 0;
  String greeting = "";

  NotificationModel? _bannerNotification;
  String? _lastShownNotificationId;
  DateTime _screenOpenedAt = DateTime.now();
  StreamSubscription<NotificationModel?>? _notifSub;

  static const Map<String, IconData> _categoryIcons = {
    "Accident": Icons.car_crash,
    "Fire": Icons.local_fire_department,
    "Road Damage": Icons.construction,
    "Fight": Icons.front_hand,
    "Harassment": Icons.person_off,
  };

  static const Map<String, Color> _categoryColors = {
    "Accident": Colors.redAccent,
    "Fire": Colors.orangeAccent,
    "Road Damage": Colors.brown,
    "Fight": Colors.deepOrange,
    "Harassment": Colors.pinkAccent,
  };

  @override
  void initState() {
    super.initState();
    setGreeting();
    _loadLastPosition();
    _screenOpenedAt = DateTime.now();

    // Only show the banner for notifications created *after* this screen
    // opened, so old/past incidents don't pop a banner every time Home loads.
    _notifSub = notificationService.latestNotificationStream().listen((
      notif,
    ) {
      if (notif == null) return;
      if (notif.id == _lastShownNotificationId) return;

      _lastShownNotificationId = notif.id;

      if (notif.createdAt == null ||
          notif.createdAt!.isBefore(_screenOpenedAt)) {
        return;
      }

      // Settings -> Incident Alerts OFF: no banner.
      if (!AppSettings.incidentAlerts.value) return;

      if (mounted) {
        setState(() => _bannerNotification = notif);
      }
    });
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
  }

  void setGreeting() {
    final hour = DateTime.now().hour;

    if (hour < 12) {
      greeting = "Good Morning";
    } else if (hour < 17) {
      greeting = "Good Afternoon";
    } else {
      greeting = "Good Evening";
    }
  }

  String currentDate() {
    final now = DateTime.now();

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

    return "${now.day} ${months[now.month - 1]}, ${now.year}";
  }

  String _relativeTime(Timestamp? ts) {
    if (ts == null) return "";
    final diff = DateTime.now().difference(ts.toDate());

    if (diff.inMinutes < 1) return "Just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes} mins ago";
    if (diff.inHours < 24) return "${diff.inHours} hrs ago";
    return "${diff.inDays} day(s) ago";
  }

  Widget dashboardCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.10),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.15),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withOpacity(.18),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // Last known location (instant, no GPS wait) -> "x km away" on cards.
  Position? _lastPosition;

  Future<void> _loadLastPosition() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final p = await Geolocator.getLastKnownPosition();
      if (p != null && mounted) setState(() => _lastPosition = p);
    } catch (_) {}
  }

  String _distanceText(Map<String, dynamic> data) {
    if (_lastPosition == null ||
        data["latitude"] == null ||
        data["longitude"] == null) {
      return "";
    }
    final d = Geolocator.distanceBetween(
      _lastPosition!.latitude,
      _lastPosition!.longitude,
      (data["latitude"] as num).toDouble(),
      (data["longitude"] as num).toDouble(),
    );
    return d < 1000
        ? "${d.toStringAsFixed(0)} m away"
        : "${(d / 1000).toStringAsFixed(1)} km away";
  }

  Color _statusColor(String status) {
    switch (status) {
      case "Verified":
        return Colors.greenAccent;
      case "Partially Verified":
        return Colors.orangeAccent;
      default:
        return Colors.white54;
    }
  }

  Widget _recentIncidentCard(Map<String, dynamic> data) {
    final category = data["category"]?.toString() ?? "Incident";
    final address = data["address"]?.toString() ?? "";
    final createdAt = data["createdAt"] as Timestamp?;

    final icon = _categoryIcons[category] ?? Icons.warning;
    final color = _categoryColors[category] ?? Colors.redAccent;

    final timeText = _relativeTime(createdAt);
    final subtitle = [
      address,
      timeText,
    ].where((e) => e.isNotEmpty).join(" • ");
    final distance = _distanceText(data);
    final status = (data["status"] ?? "Pending").toString();
    final isMine = user != null && data["userId"] == user!.uid;

    final card = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(.20),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle.isNotEmpty ? subtitle : "Just now",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _chip(status, _statusColor(status)),
                    if (distance.isNotEmpty)
                      _chip(distance, Colors.lightBlueAccent),
                    if (isMine) _chip("Your report", Colors.white),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white38),
        ],
      ),
    );

    // Tap -> open the incident on the Live Map.
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        if (data["latitude"] == null || data["longitude"] == null) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MapScreen(
              focusLat: (data["latitude"] as num).toDouble(),
              focusLng: (data["longitude"] as num).toDouble(),
              focusTitle: category,
              focusSnippet: (data["description"] ?? address).toString(),
            ),
          ),
        );
      },
      child: card,
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(
          text,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      );

  // Tabs are created the first time they are opened, then kept alive.
  final Set<int> _openedTabs = {0};

  void _goToTab(int index) {
    setState(() {
      currentIndex = index;
      _openedTabs.add(index);
    });
  }

  Widget _buildTabs(Widget homeBody) {
    Widget tab(int i, Widget Function() build) =>
        _openedTabs.contains(i) ? build() : const SizedBox.shrink();

    return PopScope(
      // Android back on Map/Report/Profile -> go to Home tab first.
      canPop: currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && currentIndex != 0) _goToTab(0);
      },
      child: IndexedStack(
        index: currentIndex,
        children: [
          homeBody,
          tab(1, () => const MapScreen()),
          tab(2, () => const ReportScreen()),
          tab(3, () => const ProfileScreen()),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff071B52),

      // Persistent bottom navigation: Home / Map / Report / Profile live in
      // one IndexedStack, so the navbar stays visible on all four tabs and
      // the map isn't reloaded every time.
      body: _buildTabs(Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xff071B52), Color(0xff0A2E73)],
              ),
            ),
          ),

          Positioned.fill(
            child: Opacity(
              opacity: .08,
              child: Image.asset("assets/pakistan_map.png", fit: BoxFit.cover),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ===============================
                  // HEADER ROW
                  // ===============================
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white,
                        child: const Icon(
                          Icons.person,
                          size: 32,
                          color: Color(0xff0A2E73),
                        ),
                      ),

                      const SizedBox(width: 15),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              greeting,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 5),
                            // Shows the profile name (editable in Profile),
                            // falls back to email like before.
                            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                              stream: user == null
                                  ? null
                                  : FirebaseFirestore.instance
                                      .collection("users")
                                      .doc(user!.uid)
                                      .snapshots(),
                              builder: (context, snap) {
                                final name = (snap.data?.data()?["fullName"] ?? "")
                                    .toString()
                                    .trim();
                                return Text(
                                  name.isNotEmpty
                                      ? name
                                      : (user?.email ?? "SafeCity User"),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      // ===============================
                      // NOTIFICATION BADGE
                      // ===============================
                      NotificationBadge(notificationService: notificationService),
                    ],
                  ),

                  const SizedBox(height: 15),

                  Text(
                    currentDate(),
                    style: const TextStyle(color: Colors.white60),
                  ),

                  const SizedBox(height: 22),

                  // Emergency live chat alerts (someone needs help / my SOS)
                  if (user != null) SosChatBanner(uid: user!.uid),

                  const SizedBox(height: 13),

                  const Text(
                    "Quick Actions",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ===============================
                  // DASHBOARD CARDS
                  // ===============================
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 18,
                    childAspectRatio: 0.95, // fits smaller screens (no overflow)
                    children: [
                      dashboardCard(
                        icon: Icons.map,
                        title: "Live Map",
                        subtitle: "Explore your city",
                        color: Colors.blueAccent,
                        onTap: () {
                          _goToTab(1);
                        },
                      ),

                      dashboardCard(
                        icon: Icons.report_problem,
                        title: "Report",
                        subtitle: "Report Incident",
                        color: Colors.orange,
                        onTap: () {
                          _goToTab(2);
                        },
                      ),

                      dashboardCard(
                        icon: Icons.sos,
                        title: "Emergency",
                        subtitle: "SOS Help",
                        color: Colors.red,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SosScreen(),
                            ),
                          );
                        },
                      ),

                      dashboardCard(
                        icon: Icons.local_fire_department,
                        title: "Heatmap",
                        subtitle: "Risk areas",
                        color: Colors.deepOrange,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const HeatmapScreen(),
                            ),
                          );
                        },
                      ),

                      dashboardCard(
                        icon: Icons.shield,
                        title: "Safety Score",
                        subtitle: "Search any area",
                        color: Colors.teal,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SafetyScoreScreen(),
                            ),
                          );
                        },
                      ),

                      dashboardCard(
                        icon: Icons.person,
                        title: "Profile",
                        subtitle: "My Account",
                        color: Colors.green,
                        onTap: () {
                          _goToTab(3);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 35),

                  // ===============================
                  // RECENT INCIDENTS (real data, last 5)
                  // ===============================
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          "Recent Incidents",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // Full community history (filters, search, details)
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const IncidentHistoryScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          "View All",
                          style: TextStyle(
                            color: Color(0xff66BB6A),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MyReportsScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          "My Reports",
                          style: TextStyle(
                            color: Color(0xff66BB6A),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 5),

                  if (user == null)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.08),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Text(
                        "Log in to see recent incidents.",
                        style: TextStyle(color: Colors.white54),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    // Latest incidents reported by ALL users (community feed).
                    // Suspicious (AIVE-flagged) reports are skipped.
                    StreamBuilder<QuerySnapshot>(
                      stream: firestore
                          .collection("reports")
                          .orderBy("createdAt", descending: true)
                          .limit(20)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            !snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                          );
                        }

                        if (snapshot.hasError) {
                          return Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(.08),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Text(
                              "Couldn't load recent incidents.\n${snapshot.error}",
                              style: const TextStyle(color: Colors.white54),
                              textAlign: TextAlign.center,
                            ),
                          );
                        }

                        final docs = (snapshot.data?.docs ?? [])
                            .where((d) => SafetyScoreService.isPublicReport(
                                d.data() as Map<String, dynamic>))
                            .take(5)
                            .toList();

                        if (docs.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(.08),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Text(
                              "No incidents reported yet. Tap Report to submit one.",
                              style: TextStyle(color: Colors.white54),
                              textAlign: TextAlign.center,
                            ),
                          );
                        }

                        return Column(
                          children: docs.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: _recentIncidentCard(data),
                            );
                          }).toList(),
                        );
                      },
                    ),

                  const SizedBox(height: 30),

                  // Logout button
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white30),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();

                        if (!context.mounted) return;

                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                          (route) => false,
                        );
                      },
                      icon: const Icon(Icons.logout, color: Colors.white),
                      label: const Text(
                        "Logout",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Info card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.security,
                          color: Color(0xff66BB6A),
                          size: 40,
                        ),
                        SizedBox(height: 12),
                        Text(
                          "SafeCity keeps communities connected and informed with real-time reporting and location-based safety services.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, height: 1.5),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 35),

                  const Divider(color: Colors.white24),

                  const SizedBox(height: 12),

                  Center(
                    child: Column(
                      children: const [
                        Text(
                          "Powered by Firebase",
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          "SafeCity © 2026",
                          style: TextStyle(color: Colors.white38),
                        ),
                        SizedBox(height: 25),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ===============================
          // NOTIFICATION BANNER (auto-dismisses in 4s)
          // ===============================
          if (_bannerNotification != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 0,
              right: 0,
              child: NotificationBanner(
                notification: _bannerNotification!,
                onView: () {
                  setState(() => _bannerNotification = null);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationScreen(),
                    ),
                  );
                },
                onDismiss: () {
                  if (mounted) setState(() => _bannerNotification = null);
                },
              ),
            ),
        ],
      )),

      // ===============================
      // BOTTOM NAVIGATION BAR
      // ===============================
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        backgroundColor: const Color(0xff071B52),
        selectedItemColor: const Color(0xff66BB6A),
        unselectedItemColor: Colors.white70,
        type: BottomNavigationBarType.fixed,
        onTap: _goToTab,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: "Map"),
          BottomNavigationBarItem(icon: Icon(Icons.report), label: "Report"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }
}