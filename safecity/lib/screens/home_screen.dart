import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';
import 'map_screen.dart';
import 'report_screen.dart';
import 'profile_screen.dart';
import 'sos_screen.dart';
import 'notification_screen.dart';
import 'my_reports_screen.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../widgets/notification_badge.dart';
import '../widgets/notification_banner.dart';

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
    "Theft": Icons.report,
    "Road Damage": Icons.construction,
    "Fight": Icons.front_hand,
    "Harassment": Icons.person_off,
  };

  static const Map<String, Color> _categoryColors = {
    "Accident": Colors.redAccent,
    "Fire": Colors.orangeAccent,
    "Theft": Colors.purpleAccent,
    "Road Damage": Colors.brown,
    "Fight": Colors.deepOrange,
    "Harassment": Colors.pinkAccent,
  };

  @override
  void initState() {
    super.initState();
    setGreeting();
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
        padding: const EdgeInsets.all(18),
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
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
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

    return Container(
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
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff071B52),

      body: Stack(
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
                            Text(
                              user?.email ?? "SafeCity User",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
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

                  const SizedBox(height: 35),

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
                    childAspectRatio: 1.05,
                    children: [
                      dashboardCard(
                        icon: Icons.map,
                        title: "Live Map",
                        subtitle: "Explore your city",
                        color: Colors.blueAccent,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MapScreen(),
                            ),
                          );
                        },
                      ),

                      dashboardCard(
                        icon: Icons.report_problem,
                        title: "Report",
                        subtitle: "Report Incident",
                        color: Colors.orange,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ReportScreen(),
                            ),
                          );
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
                        icon: Icons.person,
                        title: "Profile",
                        subtitle: "My Account",
                        color: Colors.green,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProfileScreen(),
                            ),
                          );
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
                      const Text(
                        "Recent Incidents",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MyReportsScreen(),
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
                        "Log in to see your reports here.",
                        style: TextStyle(color: Colors.white54),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    StreamBuilder<QuerySnapshot>(
                      stream: firestore
                          .collection("reports")
                          .where("userId", isEqualTo: user!.uid)
                          .orderBy("createdAt", descending: true)
                          .limit(5)
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

                        final docs = snapshot.data?.docs ?? [];

                        if (docs.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(.08),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Text(
                              "No reports yet. Tap Report to submit your first incident.",
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
      ),

      // ===============================
      // BOTTOM NAVIGATION BAR
      // ===============================
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        backgroundColor: const Color(0xff071B52),
        selectedItemColor: const Color(0xff66BB6A),
        unselectedItemColor: Colors.white70,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() {
            currentIndex = index;
          });

          switch (index) {
            case 0:
              break;
            case 1:
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MapScreen()),
              );
              break;
            case 2:
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReportScreen()),
              );
              break;
            case 3:
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
              break;
          }
        },
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