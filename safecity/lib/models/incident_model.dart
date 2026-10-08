import 'package:cloud_firestore/cloud_firestore.dart';

/// One document of the Firestore "reports" collection.
/// Field names match report_screen.dart -> submitReport().
class IncidentModel {
  final String id;
  final String reportId;
  final String category;
  final String description;
  final double latitude;
  final double longitude;
  final String address;
  final double gpsAccuracy;
  final String imageUrl;
  final String status; // AIVE: Verified / Partially Verified / Suspicious
  final double? confidence; // AIVE confidence (0.0 - 1.0)
  final DateTime? createdAt;
  final String? userId;

  const IncidentModel({
    required this.id,
    required this.reportId,
    required this.category,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.gpsAccuracy,
    required this.imageUrl,
    required this.status,
    this.confidence,
    this.createdAt,
    this.userId,
  });

  /// Returns null if the doc has no usable coordinates.
  static IncidentModel? tryFromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return null;
    if (data["latitude"] == null || data["longitude"] == null) return null;

    final ts = data["createdAt"];

    return IncidentModel(
      id: doc.id,
      reportId: (data["reportId"] ?? "").toString(),
      category: (data["category"] ?? "Other").toString(),
      description: (data["description"] ?? "").toString(),
      latitude: (data["latitude"] as num).toDouble(),
      longitude: (data["longitude"] as num).toDouble(),
      address: (data["address"] ?? "").toString(),
      gpsAccuracy: (data["gpsAccuracy"] as num?)?.toDouble() ?? 0,
      imageUrl: (data["imageUrl"] ?? "").toString(),
      status: (data["status"] ?? "Pending").toString(),
      confidence: (data["confidence"] as num?)?.toDouble(),
      createdAt: ts is Timestamp ? ts.toDate() : null,
      userId: data["userId"]?.toString(),
    );
  }

  static List<IncidentModel> listFromDocs(Iterable<DocumentSnapshot> docs) {
    final list = <IncidentModel>[];
    for (final doc in docs) {
      final m = tryFromDoc(doc);
      if (m != null) list.add(m);
    }
    return list;
  }

  Map<String, dynamic> toMap() => {
        "reportId": reportId,
        "category": category,
        "description": description,
        "latitude": latitude,
        "longitude": longitude,
        "address": address,
        "gpsAccuracy": gpsAccuracy,
        "imageUrl": imageUrl,
        "status": status,
        if (confidence != null) "confidence": confidence,
        "userId": userId,
      };
}
