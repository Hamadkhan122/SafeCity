// SafeCity - Safety Score test cases (run: flutter test test/scoring_test.dart)
// Same numbers as the TEST CASES in lib/services/safety_score_service.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:safecity/models/incident_model.dart';
import 'package:safecity/services/safety_score_service.dart';

const double lat = 34.1970, lng = 73.2463; // centre of the area
final DateTime now = DateTime(2026, 10, 3, 12);

IncidentModel report(String category,
    {double dLat = 0, Duration age = Duration.zero, String id = "x",
    String status = "Verified"}) {
  return IncidentModel(
    id: id,
    reportId: id,
    category: category,
    description: "",
    latitude: lat + dLat,
    longitude: lng,
    address: "",
    gpsAccuracy: 10,
    imageUrl: "",
    status: status,
    createdAt: now.subtract(age),
  );
}

int score(List<IncidentModel> list, {double radius = 3000}) =>
    SafetyScoreService.scoreAt(
            lat: lat, lng: lng, incidents: list, radiusMeters: radius, now: now)
        .score;

void main() {
  test("1. one verified fire today -> 97 Safe", () {
    final r = SafetyScoreService.scoreAt(
        lat: lat, lng: lng, incidents: [report("Fire")], radiusMeters: 3000, now: now);
    expect(r.score, 97);
    expect(r.label, "Safe");
  });

  test("2. two different accidents (500 m apart) -> 94", () {
    // 0.0045 deg ~ 500 m: different incidents, both inside R/3 (1 km)
    expect(
        score([report("Accident", id: "a"), report("Accident", id: "b", dLat: 0.0045)]),
        94);
  });

  test("3. same accident reported by 2 users -> 96", () {
    // 50 m apart, 10 minutes apart -> same incident, x1.25
    expect(
        score([
          report("Accident", id: "a"),
          report("Accident", id: "b", dLat: 0.00045,
              age: const Duration(minutes: -10)),
        ]),
        96); // 100 - 3 x 1.25 = 96.25 -> 96
  });

  test("3b. same accident reported by 4 users -> capped at x1.5 -> 96", () {
    expect(
        score([
          for (int i = 0; i < 4; i++) report("Accident", id: "a$i"),
        ]),
        96); // 100 - 3 x 1.5 = 95.5 -> 96
  });

  test("4. one road damage -> 98 Safe", () {
    expect(score([report("Road Damage")]), 98);
  });

  test("5. fire older than 90 days -> 100", () {
    expect(score([report("Fire", age: const Duration(days: 91))]), 100);
  });

  test("6. rejected report does not count -> 100", () {
    expect(score([report("Fire", status: "Suspicious")]), 100);
  });

  test("7. fire 5 days ago in the middle third (1.5 km) -> 100 - 3x0.7x0.6", () {
    // 0.0135 deg ~ 1.5 km
    expect(score([report("Fire", dLat: 0.0135, age: const Duration(days: 5))]),
        99); // 100 - 1.26 = 98.74 -> 99
  });
}
