import 'package:flutter/material.dart';

Future<void> showPlaceDetailsSheet({
  required BuildContext context,
  required Map<String, dynamic> place,
  required String distanceText,
  required String durationText,
  required VoidCallback onNavigate,
  VoidCallback? onCall,
}) {
  final rating = place["rating"]?.toString() ?? "N/A";
  final address = place["formatted_address"] ?? "No Address";
  final phone = place["formatted_phone_number"] ?? "Not Available";

  bool openNow = false;
  if (place["opening_hours"] != null) {
    openNow = place["opening_hours"]["open_now"] ?? false;
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) {
      return Padding(
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
            const SizedBox(height: 25),
            Text(
              place["name"] ?? "",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Icon(Icons.star, color: Colors.orange),
                const SizedBox(width: 8),
                Text(rating, style: const TextStyle(fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on, color: Colors.red),
                const SizedBox(width: 10),
                Expanded(child: Text(address)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.phone),
                const SizedBox(width: 10),
                Text(phone),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  openNow ? Icons.check_circle : Icons.cancel,
                  color: openNow ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 10),
                Text(openNow ? "Open Now" : "Closed"),
              ],
            ),
            const SizedBox(height: 16),
            if (distanceText.isNotEmpty || durationText.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Icon(Icons.route),
                        Text(distanceText),
                      ],
                    ),
                    Column(
                      children: [
                        const Icon(Icons.timer),
                        Text(durationText),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (phone != "Not Available" && onCall != null)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        onPressed: onCall,
                        icon: const Icon(Icons.call),
                        label: const Text("Call"),
                      ),
                    ),
                  ),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff0A2E73),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      onNavigate();
                    },
                    icon: const Icon(Icons.directions),
                    label: const Text("Navigate"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      );
    },
  );
}