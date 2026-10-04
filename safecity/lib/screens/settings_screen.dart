// SafeCity - Settings
// Safety: Accident Detection (+ sensitivity), SOS countdown, live location
// sharing in emergency chat, incident alerts. General: emergency contact,
// privacy policy, about, logout. Values are stored on the phone.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/accident_detection_service.dart';
import '../services/settings_service.dart';
import 'ai_test_lab_screen.dart';
import 'login_screen.dart';
import 'sos_screen.dart';

const _bg = Color(0xff071B52);
const _card = Color(0xff0E2A6B);
const _accent = Color(0xff66BB6A);

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("Settings",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          AppSettings.accidentDetection,
          AppSettings.sensitivity,
          AppSettings.sosCountdown,
          AppSettings.liveLocationSharing,
          AppSettings.incidentAlerts,
        ]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _section("Safety"),
            _group([
              _switchTile(
                icon: Icons.car_crash,
                color: const Color(0xffEF5350),
                title: "Accident Detection",
                subtitle: AppSettings.accidentDetection.value
                    ? "On · Sensitivity: "
                        "${AppSettings.sensitivityLabels[AppSettings.sensitivity.value]}"
                    : "Detect sudden impacts and alert your contact",
                value: AppSettings.accidentDetection.value,
                onChanged: (v) async {
                  if (v) {
                    final ok = await _sensitivityDialog(context);
                    if (ok == true) await AppSettings.setAccidentDetection(true);
                  } else {
                    await AppSettings.setAccidentDetection(false);
                  }
                },
              ),
              if (AppSettings.accidentDetection.value) ...[
                _tile(
                  icon: Icons.tune,
                  color: const Color(0xffFFA726),
                  title: "Detection sensitivity",
                  subtitle: AppSettings
                      .sensitivityLabels[AppSettings.sensitivity.value],
                  onTap: () => _sensitivityDialog(context),
                ),
                _tile(
                  icon: Icons.play_circle_outline,
                  color: const Color(0xff42A5F5),
                  title: "Test accident alert",
                  subtitle: "See what happens after an impact",
                  onTap: () => AccidentDetectionService.showCheck(test: true),
                ),
              ],
              _tile(
                icon: Icons.timer,
                color: const Color(0xffAB47BC),
                title: "SOS countdown",
                subtitle:
                    "Auto-send SOS after ${AppSettings.sosCountdown.value} seconds",
                onTap: () => _countdownDialog(context),
              ),
              _switchTile(
                icon: Icons.share_location,
                color: _accent,
                title: "Live Location Sharing",
                subtitle: "Share live location in the emergency chat",
                value: AppSettings.liveLocationSharing.value,
                onChanged: AppSettings.setLiveLocationSharing,
              ),
              _switchTile(
                icon: Icons.notifications_active,
                color: const Color(0xff26C6DA),
                title: "Incident Alerts",
                subtitle:
                    "Pop-up alerts for incidents near you, even when the app is closed",
                value: AppSettings.incidentAlerts.value,
                onChanged: AppSettings.setIncidentAlerts,
              ),
            ]),
            _section("Emergency"),
            _group([
              _tile(
                icon: Icons.contact_emergency,
                color: const Color(0xffEF5350),
                title: "Emergency contact",
                subtitle: "Add or change your SOS contact",
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SosScreen())),
              ),
            ]),
            _section("General"),
            _group([
              _tile(
                icon: Icons.science,
                color: const Color(0xff7E57C2),
                title: "AI Test Lab",
                subtitle: "Test the AI with a live photo (nothing is reported)",
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AiTestLabScreen())),
              ),
              _tile(
                icon: Icons.privacy_tip,
                color: const Color(0xff78909C),
                title: "Privacy Policy",
                onTap: () => _privacy(context),
              ),
              _tile(
                icon: Icons.info_outline,
                color: const Color(0xff78909C),
                title: "About SafeCity",
                subtitle: "Version 1.0.0",
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: "SafeCity",
                  applicationVersion: "1.0.0",
                  applicationLegalese:
                      "Community-driven safety incident reporting.\n"
                      "FYP — COMSATS University Islamabad, Abbottabad Campus.",
                ),
              ),
              _tile(
                icon: Icons.logout,
                color: Colors.redAccent,
                title: "Logout",
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  if (!context.mounted) return;
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (r) => false,
                  );
                },
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ---------------- dialogs ----------------

  /// Same style as the PSCA app: Low / Medium / High slider.
  static Future<bool?> _sensitivityDialog(BuildContext context) {
    double value = AppSettings.sensitivity.value.toDouble();
    return showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text("Accident Detection",
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Color(0xff2E7D32), fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Uses your phone's motion sensor to detect sudden impacts. "
                "If you don't respond, your emergency contact gets an SOS with "
                "your live location.",
                textAlign: TextAlign.center,
              ),
              const Divider(height: 28),
              const Text("Sensitivity",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              const Text(
                "Low (less reactive) · Medium (balanced) · High (more reactive)",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
              Slider(
                value: value,
                min: 0,
                max: 2,
                divisions: 2,
                activeColor: const Color(0xff2E7D32),
                label: AppSettings.sensitivityLabels[value.round()],
                onChanged: (v) => setD(() => value = v),
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text("Low"), Text("Medium"), Text("High")],
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceAround,
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text("Cancel")),
            TextButton(
              onPressed: () async {
                await AppSettings.setSensitivity(value.round());
                if (c.mounted) Navigator.pop(c, true);
              },
              child: const Text("Confirm",
                  style: TextStyle(color: Color(0xff2E7D32))),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _countdownDialog(BuildContext context) async {
    final v = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text("SOS countdown"),
        children: [
          for (final s in const [5, 10, 15, 30])
            RadioListTile<int>(
              value: s,
              groupValue: AppSettings.sosCountdown.value,
              title: Text("$s seconds"),
              onChanged: (x) => Navigator.pop(c, x),
            ),
        ],
      ),
    );
    if (v != null) await AppSettings.setSosCountdown(v);
  }

  static void _privacy(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Privacy Policy"),
        content: const SingleChildScrollView(
          child: Text(
            "• Your location is used only to report incidents, calculate "
            "safety scores and send SOS alerts.\n\n"
            "• Live location is shared only with your emergency contact, and "
            "only while an SOS chat is active.\n\n"
            "• Reports are shown publicly without your name.\n\n"
            "• Settings such as accident detection are stored on your phone.\n\n"
            "• You can turn off location sharing and accident detection at "
            "any time from Settings.",
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text("OK")),
        ],
      ),
    );
  }

  // ---------------- widgets ----------------

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.bold)),
      );

  Widget _group(List<Widget> tiles) => Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            for (int i = 0; i < tiles.length; i++) ...[
              tiles[i],
              if (i < tiles.length - 1)
                const Divider(height: 1, indent: 62, color: Colors.white10),
            ],
          ],
        ),
      );

  Widget _leading(IconData icon, Color color) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 22),
      );

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) =>
      ListTile(
        leading: _leading(icon, color),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle,
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: onTap,
      );

  Widget _switchTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      ListTile(
        leading: _leading(icon, color),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.white60, fontSize: 12)),
        trailing: Switch(
          value: value,
          activeColor: Colors.white,
          activeTrackColor: _accent,
          onChanged: onChanged,
        ),
        onTap: () => onChanged(!value),
      );
}
