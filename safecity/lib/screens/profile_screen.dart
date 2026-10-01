import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'login_screen.dart';
import 'my_reports_screen.dart';
import 'sos_screen.dart';
import 'settings_screen.dart';
import '../services/sos_chat_service.dart';

/// Profile: account details (users/{uid}), report stats, emergency contact,
/// shortcuts and logout.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const _bg = Color(0xff071B52);
  static const _card = Color(0xff0E2A6B);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("Profile",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: "Settings",
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: user == null
          ? const Center(
              child: Text("Not logged in", style: TextStyle(color: Colors.white)))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection("users")
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data() ?? {};
                final name = (data["fullName"] ?? "").toString();
                final email = (data["email"] ?? user.email ?? "").toString();
                final phone = (data["phone"] ?? "").toString();
                final contact = data["emergency_contact"] as Map<String, dynamic>?;

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: CircleAvatar(
                        radius: 44,
                        backgroundColor: Colors.white,
                        child: Text(
                          _initial(name.isNotEmpty ? name : email),
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: _bg,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        name.isNotEmpty ? name : "SafeCity User",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Center(
                      child: Text(email,
                          style: const TextStyle(color: Colors.white70)),
                    ),
                    const SizedBox(height: 20),
                    _ReportStats(uid: user.uid),
                    const SizedBox(height: 16),
                    _infoCard([
                      _row(Icons.email, "Email", email),
                      if (phone.isNotEmpty) _row(Icons.phone, "Phone", phone),
                      _row(
                        Icons.contact_emergency,
                        "Emergency contact",
                        contact == null
                            ? "Not set"
                            : "${contact["name"]} · ${contact["phone"]}",
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _actionTile(
                      context,
                      Icons.edit,
                      "Edit profile",
                      () => _openEditSheet(context, user.uid),
                    ),
                    _actionTile(
                      context,
                      Icons.list_alt,
                      "My Reports",
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MyReportsScreen()),
                      ),
                    ),
                    _actionTile(
                      context,
                      Icons.sos,
                      contact == null
                          ? "Add emergency contact"
                          : "Change emergency contact",
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SosScreen()),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (!context.mounted) return;
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text("Logout"),
                    ),
                  ],
                );
              },
            ),
    );
  }

  /// Editable fields: full name, phone, emergency contact (name + phone).
  /// Email comes from Firebase Auth login, so it is shown read-only.
  static Future<void> _openEditSheet(BuildContext context, String uid) async {
    final ref = FirebaseFirestore.instance.collection("users").doc(uid);
    final data = (await ref.get()).data() ?? {};
    final contact = data["emergency_contact"] as Map<String, dynamic>? ?? {};

    final nameC = TextEditingController(text: (data["fullName"] ?? "").toString());
    final phoneC = TextEditingController(text: (data["phone"] ?? "").toString());
    final cNameC = TextEditingController(text: (contact["name"] ?? "").toString());
    final cPhoneC = TextEditingController(text: (contact["phone"] ?? "").toString());
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    String? phoneValidator(String? v, {bool required = false}) {
      final t = (v ?? "").trim();
      if (t.isEmpty) return required ? "Required" : null;
      return RegExp(r'^\+?[0-9\-\s]{7,15}$').hasMatch(t)
          ? null
          : "Enter a valid phone number";
    }

    InputDecoration deco(String label, IconData icon) => InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.white70),
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          errorStyle: const TextStyle(color: Colors.orangeAccent),
        );

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            20 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text("Edit Profile",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: nameC,
                    style: const TextStyle(color: Colors.white),
                    decoration: deco("Full name", Icons.person),
                    validator: (v) =>
                        (v ?? "").trim().length < 3 ? "Enter your name" : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: phoneC,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white),
                    decoration: deco("Phone", Icons.phone),
                    validator: (v) => phoneValidator(v),
                  ),
                  const SizedBox(height: 18),
                  const Text("Emergency contact",
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: cNameC,
                    style: const TextStyle(color: Colors.white),
                    decoration: deco("Contact name", Icons.contact_emergency),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: cPhoneC,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white),
                    decoration: deco("Contact phone", Icons.phone_in_talk),
                    validator: (v) => phoneValidator(v,
                        required: cNameC.text.trim().isNotEmpty),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: saving
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setSheet(() => saving = true);
                            try {
                              await ref.set({
                                "fullName": nameC.text.trim(),
                                "phone": phoneC.text.trim(),
                                "phoneKey":
                                    SosChatService.phoneKey(phoneC.text.trim()),
                                if (cNameC.text.trim().isNotEmpty)
                                  "emergency_contact": {
                                    "name": cNameC.text.trim(),
                                    "phone": cPhoneC.text.trim(),
                                  },
                              }, SetOptions(merge: true));
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Profile updated")),
                                );
                              }
                            } catch (e) {
                              setSheet(() => saving = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("Could not save: $e")),
                                );
                              }
                            }
                          },
                    child: saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text("Save changes"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _initial(String s) =>
      s.trim().isEmpty ? "U" : s.trim().substring(0, 1).toUpperCase();

  Widget _infoCard(List<Widget> rows) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: rows),
      );

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  Text(value, style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _actionTile(
          BuildContext context, IconData icon, String title, VoidCallback onTap) =>
      Card(
        color: _card,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ListTile(
          leading: Icon(icon, color: Colors.white),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          onTap: onTap,
        ),
      );
}

/// Total / verified / rejected counts of the user's own reports.
/// Verified = AIVE Verified + Partially Verified,
/// Rejected = AIVE Suspicious + Rejected.
class _ReportStats extends StatelessWidget {
  final String uid;
  const _ReportStats({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection("reports")
          .where("userId", isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        bool isVerified(String s) => s == "Verified" || s == "Partially Verified";
        bool isRejected(String s) => s == "Suspicious" || s == "Rejected";
        final verified = docs
            .where((d) => isVerified((d.data()["status"] ?? "").toString()))
            .length;
        final rejected = docs
            .where((d) => isRejected((d.data()["status"] ?? "").toString()))
            .length;

        Widget stat(String label, int value, Color color) => Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: ProfileScreen._card,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text("$value",
                        style: TextStyle(
                          color: color,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        )),
                    const SizedBox(height: 2),
                    Text(label,
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            );

        return Row(
          children: [
            stat("Reports", docs.length, Colors.white),
            const SizedBox(width: 10),
            stat("Verified", verified, Colors.greenAccent),
            const SizedBox(width: 10),
            stat("Rejected", rejected, Colors.redAccent),
          ],
        );
      },
    );
  }
}
