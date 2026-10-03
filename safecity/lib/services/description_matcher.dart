// SafeCity - Description check for AIVE (English + Roman Urdu + Urdu)
// ====================================================================
// Runs fully on the phone (free, offline). It checks whether the text the
// user typed fits the category they selected.
//
//   kind      meaning                                     AIVE
//   match     describes the selected category             pass (1.0)
//   related   describes a close category (Fight/Harass.)  pass (0.7)
//   unknown   does not describe any incident              REJECT
//   other     describes a DIFFERENT category              REJECT
//   negated   says the incident is NOT there              REJECT
//             ("koi aag nahi lagi", "no fire", "آگ نہیں لگی")
//
// So "yahan aag lagi hai" + Fire + a fire photo is accepted, while
// "hello test", "aag nahi lagi" or "two cars collided" with Fire is not.
//
// Handles common Roman Urdu spelling variations:
//   - case / punctuation ignored
//   - repeated letters collapsed  (larrrai -> larai, aaag -> ag)
//   - small typos on longer words (harrasment ~ harassment)
//   - word stems                  (harass -> harassing, harassed)
//   - Urdu letter variants        (ي/ی , ك/ک , ه/ہ)

class DescriptionResult {
  final double score;
  final String? matchedCategory; // category the text looks like (or null)
  final String? flag; // reason shown in AIVE flags (or null)
  final String kind; // match / related / unknown / other / negated

  const DescriptionResult(this.score, this.matchedCategory, this.flag,
      [this.kind = "match"]);

  bool get passed => kind == "match" || kind == "related";
}

class DescriptionMatcher {
  /// Single words (Latin script). Words of 4+ letters also match as a stem
  /// (e.g. "harass" matches "harassing"); 5+ letters allow 1 typo.
  static const Map<String, List<String>> _words = {
    "Accident": [
      // English
      "collid", "crash", "accid", "injur", "bleed", "blood", "wreck", "skid", "slip", "fell", "fallen", "dead", "died", "motorbike", "bicycle", "cycle", "van", "driver", "pedestrian", "takra", "takrai", "takraya", "zakhm", "hospital",
      "accident", "crash", "crashed", "collision", "collide", "collided",
      "hit", "overturned", "overturn", "injured", "injury", "ambulance",
      "bike", "motorcycle", "car", "truck", "bus", "rickshaw", "vehicle",
      // Roman Urdu
      "hadsa", "hadsay", "hadse", "haadsa", "takkar", "takar", "tukkar",
      "gari", "gaari", "gariyon", "gaariyon", "zakhmi", "zakhmy", "ulat",
      "ulta", "ulti", "bykia", "chinchi", "rikshaw",
    ],
    "Fire": [
      // English
      "smok", "flam", "blaz", "spark", "explod", "burned", "aag", "jalna", "jalti", "jalta",
      "fire", "smoke", "burn", "burning", "burnt", "flame", "flames",
      "blaze", "explosion", "blast", "cylinder", "circuit",
      // Roman Urdu
      "aag", "ag", "agg", "aagh", "dhuan", "dhuwan", "dhoowan", "dhuaan",
      "jal", "jala", "jali", "jalna", "jalne", "jalraha", "shole", "sholay",
      "dhamaka", "dhmaka",
    ],
    "Road Damage": [
      // English
      "pothol", "crack", "damag", "uneven", "bump", "erod", "flood", "waterlog", "pani", "toota", "tuta", "broke", "dhans", "gadha", "gaddha",
      "pothole", "potholes", "road", "damage", "damaged", "broken", "crack",
      "cracks", "hole", "sinkhole", "manhole", "construction", "flooded",
      // Roman Urdu
      "sarak", "sadak", "sarrak", "gharha", "garha", "gharra",
      "tooti", "tuti", "phati", "kharab",
      "gutter", "naala", "nala",
    ],
    "Fight": [
      // English
      "punch", "kick", "slap", "stab", "shoot", "shot", "quarrel", "clash", "scuffle", "hitting", "jhagr", "larr", "marna", "maara", "pitt",
      "fight", "fighting", "fought", "brawl", "punch", "punched", "beat",
      "beating", "beaten", "attack", "attacked", "assault", "weapon",
      "knife", "gun", "violence", "violent", "mob",
      // Roman Urdu
      "larai", "laraai", "larayi", "lar", "lad", "larr", "jhagra", "jhagda",
      "jhaghra", "maar", "mar", "maarpeet", "marpeet", "peet", "pitai",
      "pitayi", "thappar", "thapar", "ghusa", "mukka", "danda", "chaku",
      "chhura", "pistol", "goli",
    ],
    "Harassment": [
      // English
      "follow", "comment", "whistl", "misbehav", "pareshan", "preshan", "ched", "chhed", "gali", "gaali",
      "harass", "harassed", "harassing", "harassment", "stalk", "stalking",
      "stalker", "tease", "teasing", "eveteasing", "catcall", "catcalling",
      "followed", "following", "touch", "touched", "touching", "grope",
      "groped", "molest", "staring", "stare", "whistle", "whistling",
      "abuse", "abusive", "threat", "threatening", "blackmail", "bully",
      "bullying", "inappropriate", "uncomfortable",
      // Roman Urdu
      "tang", "tung", "chher", "cher", "chherna", "chera", "cheda", "chedna",
      "chhedkhani", "chherkhani", "pecha", "peecha", "picha", "ghoor",
      "ghurna", "ghoorna", "ghoorta", "ghoorte", "awazen", "awaazein",
      "seeti", "badtameezi", "badtamizi", "badtameez", "badtamiz",
      "dhamki", "dhamkiyan", "chhoona",
    ],
  };

  /// Multi-word phrases (Latin script) – matched on the normalised text.
  static const Map<String, List<String>> _phrases = {
    "Accident": [
      "hit by", "ran over", "car accident", "road accident",
      "gari lag", "gari se takkar", "gaari lag", "bike gir", "gir gaya",
      "gir gayi", "ulat gayi", "ulat gaya",
    ],
    "Fire": [
      "on fire", "caught fire", "aag lag", "aag lagi", "ag lag", "ag lagi",
      "jal raha", "jal rahi", "jal rahe", "jal gaya", "jal gayi",
      "short circuit", "gas cylinder",
    ],
    "Road Damage": [
      "road broken", "broken road", "road damage", "sarak tooti",
      "sarak tuti", "sadak tooti", "sarak kharab", "sadak kharab",
      "pani khara", "gutter khula", "manhole open",
    ],
    "Fight": [
      "maar peet", "mar peet", "maar rahe", "mar rahe", "maar raha",
      "mar raha", "lar rahe", "lad rahe", "larai ho", "jhagra ho",
      "goli chali", "fire kiya",
    ],
    "Harassment": [
      "tang kar", "tang kr", "pareshan kar", "preshan kar", "peecha kar",
      "picha kar", "pecha kar", "ghoor raha", "ghoor rahe", "ghur raha",
      "awazen kas", "awaz kas", "seeti baja", "galat harkat", "ghalat harkat",
      "chher raha", "cher raha", "chhed raha", "hath lagaya", "haath lagaya",
      "follow kar", "follow kr", "galiyan de", "gaali de",
    ],
  };

  /// Urdu script – matched as substrings (after letter normalisation).
  static const Map<String, List<String>> _urdu = {
    "Accident": ["حادث", "ٹکر", "گاڑی", "زخمی", "ایکسیڈنٹ", "الٹ"],
    "Fire": ["آگ", "دھواں", "دھوا", "جل رہ", "جل گ", "شعل", "دھماک"],
    "Road Damage": ["سڑک", "گڑھ", "ٹوٹی", "کھڈ", "گٹر", "نالہ"],
    "Fight": ["لڑائی", "لڑ رہ", "جھگڑ", "مار پیٹ", "مارپیٹ", "پٹائی", "تھپڑ", "چاقو", "گولی"],
    "Harassment": ["ہراس", "تنگ", "چھیڑ", "پیچھا", "گھور", "بدتمیز", "آوازیں", "گالی", "دھمکی", "پریشان"],
  };

  /// Pairs that are close enough to count as a partial match.
  static const Set<String> _related = {
    "Fight|Harassment",
    "Harassment|Fight",
    "Accident|Road Damage",
    "Road Damage|Accident",
  };

  // ------------------------------------------------------------------
  static DescriptionResult check(String category, String text) {
    final r = _countHits(text);
    final hits = r.hits;
    final total = hits.values.fold<int>(0, (a, b) => a + b);
    final cat = category.toLowerCase();

    if (total == 0) {
      if ((r.negated[category] ?? 0) > 0) {
        return DescriptionResult(0.0, null,
            "Description says there is no $cat", "negated");
      }
      return DescriptionResult(0.0, null,
          "Description does not describe a $cat incident", "unknown");
    }

    // Category with the most hits.
    String best = hits.keys.first;
    hits.forEach((k, v) {
      if (v > hits[best]!) best = k;
    });

    final own = hits[category] ?? 0;
    if (own > 0 && own >= hits[best]!) {
      return DescriptionResult(1.0, category, null, "match");
    }
    if (own > 0 || _related.contains("$category|$best")) {
      // Mentions the category (or a close one), another more strongly.
      return DescriptionResult(0.7, best, null, "related");
    }
    if ((r.negated[category] ?? 0) > 0) {
      return DescriptionResult(
          0.0, best, "Description says there is no $cat", "negated");
    }
    return DescriptionResult(
        0.0, best, "Description describes $best, not $category", "other");
  }

  // Negation words (Latin script) - a keyword within 2 words of one of
  // these does not count ("aag nahi lagi", "no fire", "not a fight").
  static const Set<String> _negations = {
    "no", "not", "never", "without", "nahi", "nahin", "nhi", "nai", "nae",
  };

  // ------------------------------------------------------------------
  static ({Map<String, int> hits, Map<String, int> negated}) _countHits(
      String raw) {
    final hits = {for (final k in _words.keys) k: 0};
    final negated = {for (final k in _words.keys) k: 0};

    // Urdu script: phrases as substrings, short words (<= 2 letters, e.g.
    // آگ) only as whole words (so آگے "ahead" is not read as fire),
    // longer words as word-start stems.
    final urdu = _normUrdu(raw);
    final uPadded = " ${urdu.replaceAll(RegExp(r"[\s\.,!?؟،۔]+"), " ")} ";
    final uTokens = uPadded.trim().split(" ");
    final urduNeg = uTokens.any((t) => t == "نہیں" || t == "نہ" || t == "مت");
    _urdu.forEach((cat, list) {
      for (final w0 in list) {
        final w = _normUrdu(w0);
        final hit = w.contains(" ")
            ? uPadded.contains(" $w")
            : uTokens.any((t) => w.length <= 2 ? t == w : t.startsWith(w));
        if (hit) {
          if (urduNeg) {
            negated[cat] = negated[cat]! + 1;
          } else {
            hits[cat] = hits[cat]! + 1;
          }
        }
      }
    });

    // Latin script
    final text = _normLatin(raw);
    if (text.isEmpty) return (hits: hits, negated: negated);
    final padded = " $text ";
    final tokens = text.split(" ");
    final negAt = <int>[
      for (var i = 0; i < tokens.length; i++)
        if (_negations.contains(tokens[i])) i
    ];
    bool isNegated(int start, int end) =>
        negAt.any((n) => n >= start - 2 && n <= end + 2);

    _phrases.forEach((cat, list) {
      for (final p in list) {
        final ph = _normLatin(p);
        final at = padded.indexOf(" $ph");
        if (at < 0) continue;
        // token index of the phrase start / end
        final start = padded.substring(0, at).trim().isEmpty
            ? 0
            : padded.substring(0, at).trim().split(" ").length;
        final end = start + ph.split(" ").length - 1;
        if (isNegated(start, end)) {
          negated[cat] = negated[cat]! + 2;
        } else {
          hits[cat] = hits[cat]! + 2;
        }
      }
    });

    _words.forEach((cat, list) {
      final keys = list.map(_normLatin).toSet();
      for (var i = 0; i < tokens.length; i++) {
        final t = tokens[i];
        if (t.isEmpty || _negations.contains(t)) continue;
        for (final k in keys) {
          if (_wordMatch(t, k)) {
            if (isNegated(i, i)) {
              negated[cat] = negated[cat]! + 1;
            } else {
              hits[cat] = hits[cat]! + 1;
            }
            break; // one hit per token per category
          }
        }
      }
    });
    return (hits: hits, negated: negated);
  }

  static bool _wordMatch(String token, String key) {
    if (token == key) return true;
    if (token == "${key}s" || token == "${key}es") return true; // plural
    if (key.length >= 4 && token.startsWith(key)) return true; // stem
    if (key.length >= 5 &&
        token[0] == key[0] &&
        (token.length - key.length).abs() <= 1 &&
        _within1(token, key)) {
      return true; // one typo
    }
    return false;
  }

  /// True if a and b differ by at most one edit.
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

  /// lower-case, keep a-z / digits only, collapse repeated letters
  /// (larrrai -> larai, aaag -> ag, peecha -> pecha).
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
      .replaceAll(RegExp("[\u064B-\u065F\u0670]"), ""); // remove diacritics
}
