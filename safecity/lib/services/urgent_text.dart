// SafeCity - Urgent message detection for the SOS live chat
// ===========================================================
// Works on English, Roman Urdu and Urdu messages, fully on the phone.
// A message like "bachao koi mera peecha kar raha hai" or "مدد کرو" is marked
// URGENT: it is highlighted in red for the emergency contact and a
// "Call 15" shortcut is shown. Normal messages are left as they are.
//
// Same normalisation idea as DescriptionMatcher: case and punctuation are
// ignored, repeated letters are collapsed (bachaooo -> bachao), and words of
// 5+ letters allow one typo.

class UrgentText {
  UrgentText._();

  /// Single words (Latin script).
  static const List<String> _words = [
    // English
    "help", "emergency", "danger", "dangerous", "hurry", "urgent", "sos",
    "attack", "attacked", "kidnap", "kidnapped", "kidnapping", "gun",
    "knife", "bleeding", "unconscious", "fire", "trapped", "stalker",
    "following", "rescue", "scared", "afraid", "police", "ambulance",
    "hiding", "hidden",
    // Roman Urdu
    "bachao", "bachaao", "bachaw", "bachalo", "madad", "madat", "jaldi",
    "jldi", "fori", "foran", "khatra", "khatrah", "khatarnak", "dar",
    "darr", "dara", "ghabra", "aghwa", "agwa", "zakhmi", "behosh",
    "khoon", "pistol", "chaku", "chura", "aag", "police", "ambulance",
    "pecha", "peecha", "picha", "phans", "phansi", "phasi",
  ];

  /// Phrases (Latin script).
  static const List<String> _phrases = [
    "help me", "please help", "call police", "save me", "come fast",
    "come quickly", "someone is following", "i am scared", "i'm scared",
    "mujhe bachao", "mujay bachao", "mujy bachao", "meri madad",
    "madad karo", "madad kro", "jaldi aao", "jldi ao", "jaldi ao",
    "koi peecha", "peecha kar", "pecha kar", "picha kar", "maar raha",
    "mar raha", "maar rahe", "mar rahe", "dar lag", "darr lag",
    "police bulao", "1122 bulao", "15 pe call", "aag lag", "goli chal",
    "follow kar", "follow kr", "following me", "chup gayi", "chhup gayi",
    "chhup kar", "chup kar hun", "baat nahi ho sakti",
    "chupi hui", "chhupi hui", "chup gaya", "chhup gaya",
  ];

  /// Urdu script (matched as word starts / phrases).
  static const List<String> _urdu = [
    "بچاؤ", "بچاو", "بچا لو", "مدد", "جلدی", "فوری", "خطر", "ڈر",
    "پیچھا", "اغوا", "زخمی", "بے ہوش", "خون", "پستول", "چاقو", "آگ",
    "پولیس", "ایمبولینس", "مار رہ", "گولی", "چھپ کر",
  ];

  static bool isUrgent(String raw) {
    // Urdu script
    final u = _normUrdu(raw);
    final uPadded = " ${u.replaceAll(RegExp(r"[\s\.,!?؟،۔]+"), " ")} ";
    final uTokens = uPadded.trim().split(" ");
    for (final w0 in _urdu) {
      final w = _normUrdu(w0);
      final hit = w.contains(" ")
          ? uPadded.contains(" $w")
          : uTokens.any((t) => w.length <= 2 ? t == w : t.startsWith(w));
      if (hit) return true;
    }

    // Latin script
    final t = _normLatin(raw);
    if (t.isEmpty) return false;
    final padded = " $t ";
    for (final p in _phrases) {
      if (padded.contains(" ${_normLatin(p)} ") ||
          padded.contains(" ${_normLatin(p)}")) {
        return true;
      }
    }
    final keys = _words.map(_normLatin).toSet();
    for (final tok in t.split(" ")) {
      for (final k in keys) {
        if (tok == k) return true;
        if (k.length >= 5 && tok.startsWith(k)) return true;
        if (k.length >= 5 &&
            tok.isNotEmpty &&
            tok[0] == k[0] &&
            (tok.length - k.length).abs() <= 1 &&
            _within1(tok, k)) {
          return true;
        }
      }
    }
    return false;
  }

  /// True when the text is mostly Urdu/Arabic script (show it right-to-left).
  static bool isRtl(String s) {
    final rtl = RegExp(r"[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]");
    final latin = RegExp(r"[A-Za-z]");
    return rtl.allMatches(s).length > latin.allMatches(s).length;
  }

  static bool _within1(String a, String b) {
    if (a == b) return true;
    if (a.length > b.length) {
      final t = a;
      a = b;
      b = t;
    }
    int i = 0, j = 0, edits = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        i++;
        j++;
        continue;
      }
      if (++edits > 1) return false;
      if (a.length == b.length) i++;
      j++;
    }
    return edits + (b.length - j) + (a.length - i) <= 1;
  }

  static String _normLatin(String s) {
    final lower = s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), " ");
    final out = StringBuffer();
    String prev = "";
    for (final ch in lower.split("")) {
      if (ch == prev && ch != " ") continue;
      out.write(ch);
      prev = ch;
    }
    return out.toString().trim().replaceAll(RegExp(r" +"), " ");
  }

  static String _normUrdu(String s) => s
      .replaceAll("ي", "ی")
      .replaceAll("ى", "ی")
      .replaceAll("ك", "ک")
      .replaceAll("ه", "ہ")
      .replaceAll("ة", "ہ")
      .replaceAll(RegExp("[ً-ٰٟ]"), "");
}
