import 'package:flutter/material.dart';

class EtaCard extends StatelessWidget {
  final String distanceText;
  final String durationText;
  final bool isNavigating;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  const EtaCard({
    super.key,
    required this.distanceText,
    required this.durationText,
    required this.isNavigating,
    required this.onStart,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    if (distanceText.isEmpty) return const SizedBox();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(blurRadius: 12, color: Colors.black26),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  const Icon(Icons.route, color: Colors.blue),
                  const SizedBox(height: 6),
                  Text(
                    distanceText,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Text("Distance", style: TextStyle(fontSize: 12)),
                ],
              ),
              Container(width: 1, height: 45, color: Colors.grey.shade300),
              Column(
                children: [
                  const Icon(Icons.timer, color: Colors.orange),
                  const SizedBox(height: 6),
                  Text(
                    durationText,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Text("ETA", style: TextStyle(fontSize: 12)),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: onCancel,
                  icon: const Icon(Icons.close),
                  label: const Text("Cancel"),
                ),
              ),
              const SizedBox(width: 12),
              if (!isNavigating)
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff0A2E73),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: onStart,
                    icon: const Icon(Icons.navigation),
                    label: const Text("Start"),
                  ),
                ),
              if (isNavigating)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.green),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.navigation, color: Colors.green),
                        SizedBox(width: 6),
                        Text(
                          "Navigating",
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}