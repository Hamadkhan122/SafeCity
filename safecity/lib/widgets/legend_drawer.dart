import 'package:flutter/material.dart';

class LegendDrawer extends StatelessWidget {
  const LegendDrawer({super.key});

  static const List<Map<String, String>> _items = [
    {"icon": "assets/icons/police.png", "label": "Police Station"},
    {"icon": "assets/icons/hospital.png", "label": "Hospital"},
    {"icon": "assets/icons/firestation.png", "label": "Fire Station"},
    {"icon": "assets/icons/accident.png", "label": "Accident"},
    {"icon": "assets/icons/fire.png", "label": "Fire"},
    {"icon": "assets/icons/fight.png", "label": "Fight"},
    {"icon": "assets/icons/theft.png", "label": "Theft"},
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
              const SizedBox(height: 20),
              Expanded(
                child: ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Colors.white24),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return ListTile(
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
                        item["label"]!,
                        style: const TextStyle(color: Colors.white),
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