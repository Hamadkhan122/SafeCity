import 'package:flutter/material.dart';

/// Map legend. Tapping an item calls [onSelect] so the Live Map can
/// highlight (animate + zoom to) those places. [counts] shows how many of
/// each item are currently known; [selected] is the highlighted item.
class LegendDrawer extends StatelessWidget {
  final ValueChanged<String>? onSelect;
  final String? selected;
  final Map<String, int> counts;

  const LegendDrawer({
    super.key,
    this.onSelect,
    this.selected,
    this.counts = const {},
  });

  static const List<Map<String, String>> _items = [
    {"icon": "assets/icons/police.png", "label": "Police Station"},
    {"icon": "assets/icons/hospital.png", "label": "Hospital"},
    {"icon": "assets/icons/firestation.png", "label": "Fire Station"},
    {"icon": "assets/icons/accident.png", "label": "Accident"},
    {"icon": "assets/icons/fire.png", "label": "Fire"},
    {"icon": "assets/icons/fight.png", "label": "Fight"},
    {"icon": "assets/icons/road_damage.png", "label": "Road Damage"},
    {"icon": "assets/icons/harassment.png", "label": "Harassment"},
  ];

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xff071B52),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Map Legend",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Tap an item to highlight it on the map",
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Colors.white24),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final label = item["label"]!;
                    final isSelected = label == selected;
                    final count = counts[label];
                    return ListTile(
                      onTap: onSelect == null ? null : () => onSelect!(label),
                      selected: isSelected,
                      selectedTileColor: Colors.white.withValues(alpha: 0.10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (count != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                "$count",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          const SizedBox(width: 6),
                          Icon(
                            isSelected ? Icons.visibility : Icons.chevron_right,
                            color: isSelected ? Colors.greenAccent : Colors.white38,
                            size: 20,
                          ),
                        ],
                      ),
                      leading: SizedBox(
                        width: 30,
                        height: 30,
                        child: Image.asset(
                          item["icon"]!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.location_on,
                              color: Colors.white54,
                            );
                          },
                        ),
                      ),
                      title: Text(
                        label,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}