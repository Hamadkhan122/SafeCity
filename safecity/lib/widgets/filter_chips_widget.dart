import 'package:flutter/material.dart';

import '../screens/my_reports_screen.dart';

/// Category filter chips (same style as the Heatmap):
/// icon + name + count badge; the selected chip is filled with its colour.
class FilterChipsWidget extends StatelessWidget {
  final String selectedFilter;
  final ValueChanged<String> onSelected;

  /// Number of reports per category (optional). "All" is the total.
  final Map<String, int> counts;

  const FilterChipsWidget({
    super.key,
    required this.selectedFilter,
    required this.onSelected,
    this.counts = const {},
  });

  static const List<String> filters = [
    "All",
    "Accident",
    "Fire",
    "Harassment",
    "Road Damage",
    "Fight",
  ];

  static const _bg = Color(0xff071B52);
  static const _card = Color(0xff0E2A6B);

  int _count(String f) {
    if (f != "All") return counts[f] ?? 0;
    int total = 0;
    for (final c in filters.skip(1)) {
      total += counts[c] ?? 0;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final f = filters[index];
          final selected = selectedFilter == f;
          final color = f == "All"
              ? Colors.white
              : (MyReportsScreen.categoryColors[f] ?? Colors.white);
          final icon = f == "All"
              ? Icons.layers
              : (MyReportsScreen.categoryIcons[f] ?? Icons.warning);

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: selected ? color : _card.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              elevation: 3,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => onSelected(f),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: selected ? color : Colors.white24),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 16, color: selected ? _bg : color),
                      const SizedBox(width: 6),
                      Text(
                        f,
                        style: TextStyle(
                          color: selected ? _bg : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      if (counts.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: selected
                                ? _bg.withValues(alpha: 0.15)
                                : Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            "${_count(f)}",
                            style: TextStyle(
                              color: selected ? _bg : Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
