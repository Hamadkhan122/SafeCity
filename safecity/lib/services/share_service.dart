import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Opens Android's share sheet (WhatsApp, SMS, Gmail, Messenger, ...).
/// Implemented natively in MainActivity.kt ("safecity/share" channel).
/// Falls back to copying the text if the share sheet can't open.
class ShareService {
  static const _channel = MethodChannel('safecity/share');

  static Future<void> shareText(
    BuildContext context,
    String text, {
    String title = "Share via",
  }) async {
    try {
      final ok = await _channel
          .invokeMethod<bool>('shareText', {'text': text, 'title': title});
      if (ok == true) return;
    } catch (e) {
      debugPrint("Share sheet failed: $e");
    }

    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Copied — paste it in any app to share.")),
      );
    }
  }

  static String locationMessage(double lat, double lng) =>
      "My live location (SafeCity): https://www.google.com/maps?q=$lat,$lng";
}
