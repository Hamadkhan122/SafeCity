// SafeCity - "Is this still happening?" card (Incident Details)
// Shows ACTIVE / CLEARED at run time and lets any user answer
// "Still there" or "Cleared now" (see IncidentStatusService).

import 'package:flutter/material.dart';

import '../models/incident_model.dart';
import '../services/incident_status_service.dart';

class IncidentStatusCard extends StatefulWidget {
  final String docId;
  final String category;
  final DateTime? createdAt;
  final String? reporterId;
  final bool isTest;

  const IncidentStatusCard({
    super.key,
    required this.docId,
    required this.category,
    required this.createdAt,
    required this.reporterId,
    this.isTest = false,
  });

  @override
  State<IncidentStatusCard> createState() => _IncidentStatusCardState();
}

class _IncidentStatusCardState extends State<IncidentStatusCard> {
  bool _sending = false;

  Future<void> _vote(bool cleared) async {
    setState(() => _sending = true);
    try {
      await IncidentStatusService.vote(widget.docId, cleared);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(cleared
              ? "Thanks! Marked as cleared."
              : "Thanks! Marked as still happening.")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Could not save: $e")));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<IncidentVotes>(
      stream: IncidentStatusService.watchVotesOf(widget.docId),
      builder: (context, snap) {
        final v = snap.data ?? const IncidentVotes();
        final model = IncidentModel(
          id: widget.docId,
          reportId: "",
          category: widget.category,
          description: "",
          latitude: 0,
          longitude: 0,
          address: "",
          gpsAccuracy: 0,
          imageUrl: "",
          status: "",
          createdAt: widget.createdAt,
          userId: widget.reporterId,
          isTest: widget.isTest,
        );
        final reason = IncidentStatusService.endReason(model, v);
        final active = reason == null;
        final color = active ? const Color(0xffEF5350) : const Color(0xff2E7D32);

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(active ? Icons.warning_amber_rounded : Icons.verified,
                      color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      active
                          ? "ACTIVE - avoid this area"
                          : "CLEARED - area safe again",
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                active
                    ? "Still happening? Your answer updates the map and safe "
                        "routes for everyone."
                    : (reason ?? ""),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                "Answers: ${v.cleared} cleared · ${v.still} still there"
                "${v.myVote == null ? "" : " · you: ${v.myVote == "cleared" ? "cleared" : "still there"}"}",
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38)),
                      onPressed: _sending ? null : () => _vote(false),
                      icon: const Icon(Icons.report, size: 18),
                      label: const Text("Still there"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff2E7D32),
                          foregroundColor: Colors.white),
                      onPressed: _sending ? null : () => _vote(true),
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: const Text("Cleared now"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
