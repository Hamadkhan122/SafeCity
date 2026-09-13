import 'package:flutter/material.dart';

class SearchBarWidget extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final List<dynamic> results;
  final bool searching;
  final void Function(Map<String, dynamic> item) onResultTap;

  const SearchBarWidget({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.results,
    required this.searching,
    required this.onResultTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(blurRadius: 8, color: Colors.black26),
            ],
          ),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: "Search anywhere...",
              icon: Icon(Icons.search),
            ),
          ),
        ),

        const SizedBox(height: 10),

        if (results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(blurRadius: 8, color: Colors.black26),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: results.length > 5 ? 5 : results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = results[index];
                final description = item["description"] ?? "Unknown";

                return ListTile(
                  leading: const Icon(Icons.location_on, color: Colors.red),
                  title: Text(
                    description,
                    style: const TextStyle(fontSize: 14),
                  ),
                  onTap: () => onResultTap(item),
                );
              },
            ),
          ),

        if (searching)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: SizedBox(
              height: 25,
              width: 25,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
      ],
    );
  }
}