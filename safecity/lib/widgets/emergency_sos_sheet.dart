import 'package:flutter/material.dart';

Future<void> showEmergencySosSheet({
  required BuildContext context,
  required Map<String, dynamic>? nearestPolice,
  required Map<String, dynamic>? nearestHospital,
  required Map<String, dynamic>? nearestFire,
  required void Function(Map<String, dynamic> place) onNavigateTo,
  required void Function(String number) onCall,
  required VoidCallback onShareLocation,
}) {
  Widget tile({
    required IconData icon,
    required Color color,
    required String label,
    required Map<String, dynamic>? place,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.15),
        child: Icon(icon, color: color),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(place != null ? (place["name"] ?? "Unknown") : "Not found nearby"),
      trailing: place != null ? const Icon(Icons.chevron_right) : null,
      onTap: place != null ? () => onNavigateTo(place) : null,
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  "Emergency Mode",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              tile(
                icon: Icons.local_police,
                color: Colors.blue,
                label: "Nearest Police",
                place: nearestPolice,
              ),
              tile(
                icon: Icons.local_hospital,
                color: Colors.red,
                label: "Nearest Hospital",
                place: nearestHospital,
              ),
              tile(
                icon: Icons.fire_truck,
                color: Colors.orange,
                label: "Nearest Fire Station",
                place: nearestFire,
              ),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.redAccent,
                  child: Icon(Icons.call, color: Colors.white),
                ),
                title: const Text("Emergency Call (Rescue 1122)"),
                onTap: () => onCall("1122"),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.green,
                  child: Icon(Icons.share_location, color: Colors.white),
                ),
                title: const Text("Share Live Location"),
                onTap: onShareLocation,
              ),
            ],
          ),
        ),
      );
    },
  );
}