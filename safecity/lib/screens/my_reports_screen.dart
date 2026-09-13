import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MyReportsScreen extends StatelessWidget {
  const MyReportsScreen({super.key});

  static const Map<String, IconData> categoryIcons = {
    "Accident": Icons.car_crash,
    "Fire": Icons.local_fire_department,
    "Theft": Icons.report,
    "Road Damage": Icons.construction,
    "Fight": Icons.front_hand,
    "Harassment": Icons.person_off,
  };

  static const Map<String, Color> categoryColors = {
    "Accident": Colors.redAccent,
    "Fire": Colors.orangeAccent,
    "Theft": Colors.purpleAccent,
    "Road Damage": Colors.brown,
    "Fight": Colors.deepOrange,
    "Harassment": Colors.pinkAccent,
  };

  static Color statusColor(String status) {
    switch (status) {
      case "Resolved":
        return Colors.green;
      case "Rejected":
        return Colors.red;
      case "In Progress":
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  static String formatTimestamp(Timestamp? ts) {
    if (ts == null) return "";
    final dt = ts.toDate();
    final diff = DateTime.now().difference(dt);

    if (diff.inMinutes < 1) return "Just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes} min ago";
    if (diff.inHours < 24) return "${diff.inHours} hr ago";
    if (diff.inDays < 7) return "${diff.inDays} day(s) ago";

    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];
    return "${dt.day} ${months[dt.month - 1]} ${dt.year}";
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xff071B52),
      appBar: AppBar(
        backgroundColor: const Color(0xff071B52),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "My Reports",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: uid == null
          ? const Center(
              child: Text(
                "Please log in to view your reports.",
                style: TextStyle(color: Colors.white70),
              ),
            )
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("reports")
                  .where("userId", isEqualTo: uid)
                  .orderBy("createdAt", descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        "Couldn't load reports.\n${snapshot.error}",
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(30),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox, color: Colors.white38, size: 60),
                          SizedBox(height: 16),
                          Text(
                            "No reports yet",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            "Reports you submit will show up here.",
                            style: TextStyle(color: Colors.white38),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;

                    final category = data["category"]?.toString() ?? "Incident";
                    final description = data["description"]?.toString() ?? "";
                    final status = data["status"]?.toString() ?? "Pending";
                    final address = data["address"]?.toString() ?? "";
                    final reportId = data["reportId"]?.toString() ?? "";
                    final createdAt = data["createdAt"] as Timestamp?;

                    final icon = categoryIcons[category] ?? Icons.report_problem;
                    final color = categoryColors[category] ?? Colors.blueGrey;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(.2),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(icon, color: color),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      category,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    if (reportId.isNotEmpty)
                                      Text(
                                        "#$reportId",
                                        style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor(status).withOpacity(.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: statusColor(status)),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    color: statusColor(status),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              if (address.isNotEmpty) ...[
                                const Icon(
                                  Icons.location_on,
                                  color: Colors.white38,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    address,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ] else
                                const Spacer(),
                              Text(
                                formatTimestamp(createdAt),
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}