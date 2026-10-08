import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/parsers.dart';
import '../utils/search_keywords.dart';
import 'enums.dart';

/// A lost or found report: the document `reports/{id}`.
///
/// The `*Map` helpers at the bottom build the exact maps that
/// firestore.rules accepts. Use them instead of writing maps by hand.
class Report {
  const Report({
    required this.id,
    required this.type,
    required this.userId,
    required this.reporterName,
    required this.itemName,
    required this.category,
    required this.description,
    required this.additionalDetails,
    required this.location,
    required this.locationDetail,
    required this.eventAt,
    required this.imageUrl,
    required this.imagePath,
    required this.status,
    required this.hidden,
    required this.matchStatus,
    required this.keywords,
    required this.createdAt,
    required this.updatedAt,
    this.matchCount = 0,
    this.bestMatchScore = 0,
    this.lastMatchedAt,
    this.hiddenReason = '',
    this.hiddenBy = '',
    this.returnedAt,
    this.returnedTo = '',
    this.resolvedBy = '',
  });

  final String id;
  final ReportType type;
  final String userId;
  final String reporterName;
  final String itemName;
  final String category;
  final String description;
  final String additionalDetails;
  final String location;
  final String locationDetail;

  /// When the item was lost/found (the form's date and time combined).
  final DateTime eventAt;

  final String imageUrl;
  final String imagePath;
  final ReportStatus status;

  /// Admin moderation switch. Hidden reports are visible only to the owner and admins.
  final bool hidden;

  final MatchState matchStatus;
  final List<String> keywords;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Written by the Python service only.
  final int matchCount;
  final int bestMatchScore;
  final DateTime? lastMatchedAt;

  // Written by an admin when hiding a report.
  final String hiddenReason;
  final String hiddenBy;

  // Written when the item is returned.
  final DateTime? returnedAt;
  final String returnedTo;
  final String resolvedBy;

  bool get isLost => type == ReportType.lost;
  bool get isFound => type == ReportType.found;
  bool get isActive => status == ReportStatus.active;
  bool get isClaimed => status == ReportStatus.claimed;
  bool get isReturned => status == ReportStatus.returned;
  bool get hasImage => imageUrl.isNotEmpty;
  bool get hasMatches => matchCount > 0;

  /// "Library - 2nd floor" or just "Library".
  String get locationLabel =>
      locationDetail.isEmpty ? location : '$location - $locationDetail';

  bool isOwnedBy(String? uid) => uid != null && uid == userId;

  factory Report.fromMap(String id, Map<String, dynamic> map) {
    final now = DateTime.now();
    return Report(
      id: id,
      type: ReportType.fromValue(readString(map, 'type')),
      userId: readString(map, 'userId'),
      reporterName: readString(map, 'reporterName'),
      itemName: readString(map, 'itemName'),
      category: readString(map, 'category'),
      description: readString(map, 'description'),
      additionalDetails: readString(map, 'additionalDetails'),
      location: readString(map, 'location'),
      locationDetail: readString(map, 'locationDetail'),
      eventAt: readDateTimeOr(map, 'eventAt', now),
      imageUrl: readString(map, 'imageUrl'),
      imagePath: readString(map, 'imagePath'),
      status: ReportStatus.fromValue(readString(map, 'status')),
      hidden: readBool(map, 'hidden'),
      matchStatus: MatchState.fromValue(readString(map, 'matchStatus')),
      keywords: readStringList(map, 'keywords'),
      createdAt: readDateTimeOr(map, 'createdAt', now),
      updatedAt: readDateTimeOr(map, 'updatedAt', now),
      matchCount: readInt(map, 'matchCount'),
      bestMatchScore: readInt(map, 'bestMatchScore'),
      lastMatchedAt: readDateTime(map, 'lastMatchedAt'),
      hiddenReason: readString(map, 'hiddenReason'),
      hiddenBy: readString(map, 'hiddenBy'),
      returnedAt: readDateTime(map, 'returnedAt'),
      returnedTo: readString(map, 'returnedTo'),
      resolvedBy: readString(map, 'resolvedBy'),
    );
  }

  factory Report.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Report.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});
  }

  // ---------------------------------------------------------------------
  // Maps for writing. Each one is checked against firestore.rules.
  // ---------------------------------------------------------------------

  /// A brand-new report: exactly the 19 keys the create rule demands.
  static Map<String, dynamic> createMap({
    required String id,
    required ReportType type,
    required String userId,
    required String reporterName,
    required String itemName,
    required String category,
    required String description,
    required String additionalDetails,
    required String location,
    required String locationDetail,
    required DateTime eventAt,
    required String imageUrl,
    required String imagePath,
  }) {
    final cleanName = itemName.trim();
    final cleanDescription = description.trim();
    final cleanDetail = locationDetail.trim();
    return <String, dynamic>{
      'id': id,
      'type': type.value,
      'userId': userId,
      'reporterName': reporterName.trim(),
      'itemName': cleanName,
      'category': category,
      'description': cleanDescription,
      'additionalDetails': additionalDetails.trim(),
      'location': location,
      'locationDetail': cleanDetail,
      'eventAt': Timestamp.fromDate(eventAt),
      'imageUrl': imageUrl,
      'imagePath': imagePath,
      'status': ReportStatus.active.value,
      'hidden': false,
      'matchStatus': MatchState.pending.value,
      'keywords': SearchKeywords.forReport(
        itemName: cleanName,
        category: category,
        location: location,
        locationDetail: cleanDetail,
        description: cleanDescription,
      ),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// The owner edits the report. Matching is reset to "pending" because the
  /// content changed, so the service should be asked to match again.
  static Map<String, dynamic> contentUpdateMap({
    required String itemName,
    required String category,
    required String description,
    required String additionalDetails,
    required String location,
    required String locationDetail,
    required DateTime eventAt,
    required String imageUrl,
    required String imagePath,
  }) {
    final cleanName = itemName.trim();
    final cleanDescription = description.trim();
    final cleanDetail = locationDetail.trim();
    return <String, dynamic>{
      'itemName': cleanName,
      'category': category,
      'description': cleanDescription,
      'additionalDetails': additionalDetails.trim(),
      'location': location,
      'locationDetail': cleanDetail,
      'eventAt': Timestamp.fromDate(eventAt),
      'imageUrl': imageUrl,
      'imagePath': imagePath,
      'keywords': SearchKeywords.forReport(
        itemName: cleanName,
        category: category,
        location: location,
        locationDetail: cleanDetail,
        description: cleanDescription,
      ),
      'matchStatus': MatchState.pending.value,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// active <-> claimed (used when a claim is approved or revoked).
  /// Never pass `returned` here: use [returnedUpdateMap].
  static Map<String, dynamic> statusUpdateMap(ReportStatus status) {
    return <String, dynamic>{
      'status': status.value,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Marks the item as handed back. The rules require all three details.
  static Map<String, dynamic> returnedUpdateMap({
    required String resolvedBy,
    required String returnedTo,
  }) {
    return <String, dynamic>{
      'status': ReportStatus.returned.value,
      'returnedAt': FieldValue.serverTimestamp(),
      'returnedTo': returnedTo.trim(),
      'resolvedBy': resolvedBy,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// The owner records whether the last matching run worked.
  /// Only `pending` and `failed` are allowed from the app.
  static Map<String, dynamic> matchStatusUpdateMap(MatchState state) {
    return <String, dynamic>{
      'matchStatus': state.value,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Admin only: hide or show a report.
  static Map<String, dynamic> hideUpdateMap({
    required bool hidden,
    required String adminUid,
    String reason = '',
  }) {
    return <String, dynamic>{
      'hidden': hidden,
      'hiddenBy': adminUid,
      'hiddenReason': reason.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
