import 'package:flutter/material.dart';

import '../services/safety_score_service.dart';

/// Compact card shown on the map: "Area Safety 82 · Safe".
/// Tap -> expands to show category breakdown.
class SafetyScoreCard extends StatelessWidget {
  final String title;
  final int score;
  final SafetyLevel level;
  final String subtitle;
  final VoidCallback? onTap;

  const SafetyScoreCard({
    super.key,
    required this.title,
    required this.score,
    required this.level,
    required this.subtitle,
    this.onTap,
  });

  Color get _color {
    switch (level) {
      case SafetyLevel.safe:
        return const Color(0xff2E7D32);
      case SafetyLevel.moderate:
        return const Color(0xffF9A825);
      case SafetyLevel.unsafe:
        return const Color(0xffC62828);
    }
  }

  String get _label {
    switch (level) {
      case SafetyLevel.safe:
        return "Safe";
      case SafetyLevel.moderate:
        return "Moderate";
      case SafetyLevel.unsafe:
        return "Unsafe";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: score / 100,
                      strokeWidth: 5,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(_color),
                    ),
                    Text(
                      "$score",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "$title · $_label",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _color,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet with full breakdown for a point (used on long-press and
/// when the user taps the card).
Future<void> showSafetyDetailsSheet({
  required BuildContext context,
  required String title,
  required SafetyResult result,
  double radiusMeters = SafetyScoreService.defaultRadiusMeters,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) {
      final entries = result.categoryCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
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
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  "${result.score}",
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: result.color,
                  ),
                ),
                const SizedBox(width: 8),
                Text("/ 100  ·  ${result.label}",
                    style: TextStyle(fontSize: 16, color: result.color)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "${result.incidentCount} incident(s) within "
              "${(radiusMeters / 1000).toStringAsFixed(0)} km",
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 14),
            if (entries.isEmpty)
              const Text("No reported incidents nearby.")
            else
              ...entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(child: Text(e.key)),
                      Text("${e.value}",
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 10),
            const Text(
              "Score considers severity, how recent and how close each report "
              "is, and whether it has been verified.",
              style: TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ],
        ),
      );
    },
  );
}
