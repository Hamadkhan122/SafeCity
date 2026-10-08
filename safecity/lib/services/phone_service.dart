import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Places calls from inside the app.
///
/// Uses a DIRECT call (CALL_PHONE permission) so that when the call ends
/// Android returns straight to SafeCity, instead of leaving the user on the
/// dialer's "recents" screen. If the permission is denied, it falls back to
/// opening the normal dialer with the number filled in.
class PhoneService {
  // Implemented natively in android/.../MainActivity.kt (ACTION_CALL).
  static const _channel = MethodChannel('safecity/phone');

  static String _clean(String number) =>
      number.replaceAll(RegExp(r'[^0-9+]'), '');

  static Future<void> call(
    BuildContext context,
    String number, {
    String? label,
    bool confirm = true,
  }) async {
    final cleaned = _clean(number);
    if (cleaned.isEmpty) return;

    if (confirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              const Icon(Icons.call, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(child: Text(label != null ? "Call $label?" : "Call?")),
            ],
          ),
          content: Text(
            cleaned,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.call),
              label: const Text("Call"),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    // 1) Direct call -> returns to the app when the call ends.
    try {
      final started = await _channel
          .invokeMethod<bool>('directCall', {'number': cleaned});
      if (started == true) return;
    } catch (e) {
      debugPrint("Direct call failed: $e");
    }

    // 2) Fallback: open dialer with the number.
    try {
      final opened = await launchUrl(
        Uri(scheme: 'tel', path: cleaned),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open the phone dialer")),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open the phone dialer")),
        );
      }
    }
  }
}
