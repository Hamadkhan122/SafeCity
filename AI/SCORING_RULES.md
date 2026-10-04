# SafeCity – Scoring Rules (Report Verification + Safety Score)

The same rules are used everywhere: AIVE at submit, Verification dialog, Incident Details,
Live Map, Safety Score screen, Heatmap and Safe Route.
Code: `lib/services/aive_service.dart` and `lib/services/safety_score_service.dart`.

---

## 1. Report Verification (AIVE) – 100 points

| Check | Max | Exact rule |
|---|---|---|
| **Photo** | **40** | `round(AI confidence × 40)` (91 % → 36). AI confidence = model probability for the selected category (Harassment: `max(people visible, violence)`) |
| **Location (GPS)** | **25** | accuracy ≤ 20 m → 25 · ≤ 50 m → 20 · ≤ 100 m → 13 · > 100 m → 5 · **fake (mock) GPS → 0 + REJECT** |
| **Description** | **15** | matches the category → 15 · close category (Fight↔Harassment, Accident↔Road Damage) → 11 · **other category / no incident / "not there" → 0 + REJECT** |
| **Time** | **10** | Photo age (capture → submit): ≤ 5 min → 5 · ≤ 15 min → 3 · older → 1. Location-fix age: ≤ 2 min → 5 · ≤ 10 min → 3 · older → 1. Time = photo part + location part |
| **Nearby reports** | **10** | matching reports by OTHER users: none → 5 · one → 8 · two or more → 10 |

**Verification score = Photo + Location + Description + Time + Nearby** (whole numbers, 0–100).

### SAME INCIDENT rule (one rule for the whole app)
Two reports are the **same incident** when: **same category AND ≤ 200 m apart AND ≤ 3 hours apart.**
- By another user → counts as a *Nearby report*.
- By the same user → **Duplicate → REJECT**.

**Spam:** the user already has 5 reports in the last 60 minutes → the next one is **REJECTED**.

### Mandatory checks (any failure = REJECTED)
1. Photo present and shows the selected incident (Fight: fighting visible; Harassment: people visible)
2. Live photo – not a photo of a laptop / phone / TV screen
3. Description – not wrong category, not empty of incident words, not "not there"
4. GPS not fake (mock)
5. Not a duplicate
6. Not spam

## 2. Verification Decision

```
if any mandatory check fails:            status = REJECTED
else:
    strikes = strikes of this user in the last 30 days
    required = 80 if strikes >= 2 else 60
    status = VERIFIED if score >= required else REJECTED
```

**Strike** (proof saved on the report: photo + AI checks). A strike is added when a report is
rejected for: photo of a screen, fake GPS, duplicate, or spam.
- 2+ strikes (30 days) → 80 points needed
- 3–4 strikes → reporting blocked 7 days after the last strike
- 5+ strikes → reporting blocked 30 days after the last strike
- strikes older than 30 days stop counting

## 3. AI Confidence vs Verification Score
- **AI confidence** = photo model %, e.g. 91 %.
- **Photo points** = 36/40.
- **Verification score** = sum of all checks, e.g. 91/100.

UI labels: "AI confidence 91 %", "Photo (36/40)", "Verification score 91/100".

---

## 4. Safety Score

Counted reports: every report that is not Rejected.

**Duplicates:** reports of the SAME INCIDENT (rule above) form one incident.
Location and time = the **first** report. With n reports:

```
duplicates factor = 1 + 0.25 × min(n − 1, 2)      → 1.00 / 1.25 / 1.50
```

**Formula** (R = radius, d = distance of the incident from the centre):

```
deduction_i  = W(category) × T(age) × D(d, R) × duplicates factor
SafetyScore  = round(100 − Σ deduction_i), never below 0
```

| W (category) | | T (age of first report) | | D (distance) | |
|---|---|---|---|---|---|
| Fire | 25 | ≤ 1 day | 1.0 | d ≤ R/3 | 1.0 |
| Accident | 20 | ≤ 7 days | 0.7 | d ≤ 2R/3 | 0.6 |
| Fight | 15 | ≤ 30 days | 0.4 | d ≤ R | 0.3 |
| Harassment | 12 | ≤ 90 days | 0.2 | d > R | 0 |
| Road Damage | 6 | > 90 days | 0 | | |

**Levels:** 70–100 Safe · 40–69 Moderate · 0–39 Unsafe

**Radius R used by the system**

| Screen | R |
|---|---|
| Live Map card | 1 km around the user |
| Safety Score screen | 1 / 2 / 3 / 5 km (chips, default 3 km) |
| Heatmap | 700 m around each zone centre (zone = reports within 500 m of its most serious report) |
| Safe Route | 300 m around points every 150 m on the route; route score = round(0.7 × average + 0.3 × worst point) |

## 5. Heatmap
Same numerical Safety Score, different labels:
85–100 **Low** · 70–84 **Medium** · 40–69 **Medium-High** · 0–39 **High**

---

## 6. Test Cases (centre of a 3 km radius)

| # | Case | Calculation | Result |
|---|---|---|---|
| 1 | One verified fire today | 100 − 25×1.0×1.0 | **75 Safe** |
| 2 | Two different accidents today (500 m apart) | 100 − 20 − 20 | **60 Moderate** |
| 3 | Same accident, 2 users (50 m, 10 min apart) | 100 − 20×1.25 | **75 Safe** |
| 3b | Same accident, 4 users | 100 − 20×1.50 | **70 Safe** |
| 4 | One road damage today | 100 − 6 | **94 Safe** |
| 5 | Fire older than 90 days | 100 − 25×0 | **100 Safe** |
| 6 | Fire 5 days ago, 1.5 km away | 100 − 25×0.7×0.6 = 89.5 | **90 Safe** (Heatmap: Low) |

Run them: `flutter test test/scoring_test.dart`

### Verification examples

| Case | Photo | GPS | Description | Time | Nearby | Total | Decision |
|---|---|---|---|---|---|---|---|
| Fire, 91 % confidence, ±12 m, "dukan mein aag lagi hai", photo 2 min old, fix 1 min, first report | 36 | 25 | 15 | 5+5 | 5 | **91** | VERIFIED |
| Same, but ±150 m GPS and photo 20 min old | 36 | 5 | 15 | 1+5 | 5 | **67** | VERIFIED (normal user) / REJECTED (2+ strikes) |
| Road damage, 55 % confidence, ±60 m, "sarak toot gayi", fix 12 min old | 22 | 13 | 15 | 5+1 | 5 | **61** | VERIFIED |
| Fire photo, description "two cars collided" | 36 | 25 | 0 ✗ | 10 | 5 | 76 | REJECTED (wrong description) |
| Any report with fake GPS | – | 0 ✗ | – | – | – | – | REJECTED (+ strike) |

## 7. UI display format

Verification dialog / Incident Details:
```
AI Verification: Verified (91/100 points)
✓ Live photo: Live camera photo (not a photo of a screen)
✓ Photo (36/40): AI confidence 91% · photo shows fire
✓ Location (GPS) (25/25): Real GPS location (±12 m)
✓ Description (15/15): Description matches Fire
✓ Time (10/10): Photo taken 2 min before submitting (5/5) · location 1 min old (5/5)
✓ Nearby reports (5/10): First report of this incident in the area
✓ Duplicate: Not a duplicate
✓ Spam: Normal reporting rate
```
Rejected: the first line is red "Rejected because: Photo, Description".
Incident Details bars: "Verification score 91/100", "Photo AI confidence 91%", "Location 25/25", ...
