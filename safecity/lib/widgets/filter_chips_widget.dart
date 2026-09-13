import 'package:flutter/material.dart';

class FilterChipsWidget extends StatelessWidget {
  final String selectedFilter;
  final ValueChanged<String> onSelected;

  const FilterChipsWidget({
    super.key,
    required this.selectedFilter,
    required this.onSelected,
  });

  static const List<String> filters = [
    "All",
    "Accident",
    "Fire",
    "Theft",
    "Harassment",
    "Road Damage",
    "Fight",
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final selected = selectedFilter == filter;

          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(filter, style: const TextStyle(fontSize: 11)),
              selected: selected,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              onSelected: (_) => onSelected(filter),
            ),
          );
        },
      ),
    );
  }
}