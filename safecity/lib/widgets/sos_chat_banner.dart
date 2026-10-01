import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../screens/sos_chat_screen.dart';
import '../services/sos_chat_service.dart';

/// Home-screen banner for active emergency chats:
///  - someone who saved me as emergency contact pressed SOS -> red alert
///  - my own SOS is still active -> reminder to reopen the chat
class SosChatBanner extends StatelessWidget {
  final String uid;
  const SosChatBanner({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: SosChatService.myActiveChats(uid),
      builder: (context, snap) {
        final chats = snap.data ?? [];
        if (chats.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            for (final c in chats) _card(context, c.id, c.data()),
          ],
        );
      },
    );
  }

  Widget _card(BuildContext context, String chatId, Map<String, dynamic> c) {
    final mine = c["ownerId"] == uid;
    final title = mine
        ? "Your SOS is active"
        : "🚨 ${(c["ownerName"] ?? "Someone")} needs help!";
    final subtitle = mine
        ? "Tap to open your emergency chat"
        : (c["lastMessage"] ?? "Tap to open the emergency chat").toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: mine ? const Color(0xffB71C1C) : const Color(0xffD32F2F),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SosChatScreen(chatId: chatId)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Icon(Icons.forum, color: Color(0xffD32F2F)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
