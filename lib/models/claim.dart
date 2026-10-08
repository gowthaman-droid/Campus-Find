import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/constants.dart';
import '../utils/parsers.dart';
import 'enums.dart';

/// A request to get a found item back: the document
/// `claims/{reportId}_{claimantUid}`.
class Claim {
  const Claim({
    required this.claimId,
    required this.reportId,
    required this.reportOwnerId,
    required this.claimantId,
    required this.claimantName,
    required this.claimantPhone,
    required this.reportItemName,
    required this.message,
    required this.verificationDetails,
    required this.status,
    required this.createdAt,
    this.reviewedAt,
    this.reviewedBy = '',
    this.reviewNote = '',
    this.completedAt,
  });

  final String claimId;
  final String reportId;

  /// The finder: owner of the found report. Reviews the claim.
  final String reportOwnerId;

  final String claimantId;
  final String claimantName;
  final String claimantPhone;
  final String reportItemName;

  /// Why the claimant says the item is theirs.
  final String message;

  /// Proof only the real owner would know (marks, contents, serial number).
  final String verificationDetails;

  final ClaimStatus status;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String reviewedBy;
  final String reviewNote;
  final DateTime? completedAt;

  bool get isPending => status == ClaimStatus.pending;
  bool get isApproved => status == ClaimStatus.approved;
  bool get isRejected => status == ClaimStatus.rejected;
  bool get isCompleted => status == ClaimStatus.completed;

  /// Still needs attention (waiting for review or waiting for hand-over).
  bool get isOpen => isPending || isApproved;

  /// Once approved, the claimant may see the finder's contact details.
  bool get revealsContact => isApproved || isCompleted;

  /// Document id of the claim a person makes on a report.
  static String idFor(String reportId, String claimantUid) =>
      FirestorePaths.claimId(reportId, claimantUid);

  factory Claim.fromMap(String id, Map<String, dynamic> map) {
    return Claim(
      claimId: id,
      reportId: readString(map, 'reportId'),
      reportOwnerId: readString(map, 'reportOwnerId'),
      claimantId: readString(map, 'claimantId'),
      claimantName: readString(map, 'claimantName'),
      claimantPhone: readString(map, 'claimantPhone'),
      reportItemName: readString(map, 'reportItemName'),
      message: readString(map, 'message'),
      verificationDetails: readString(map, 'verificationDetails'),
      status: ClaimStatus.fromValue(readString(map, 'status')),
      createdAt: readDateTimeOr(map, 'createdAt', DateTime.now()),
      reviewedAt: readDateTime(map, 'reviewedAt'),
      reviewedBy: readString(map, 'reviewedBy'),
      reviewNote: readString(map, 'reviewNote'),
      completedAt: readDateTime(map, 'completedAt'),
    );
  }

  factory Claim.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Claim.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});
  }

  /// A new claim: exactly the 11 keys the create rule demands.
  static Map<String, dynamic> createMap({
    required String reportId,
    required String reportOwnerId,
    required String claimantId,
    required String claimantName,
    required String claimantPhone,
    required String reportItemName,
    required String message,
    required String verificationDetails,
  }) {
    return <String, dynamic>{
      'claimId': idFor(reportId, claimantId),
      'reportId': reportId,
      'reportOwnerId': reportOwnerId,
      'claimantId': claimantId,
      'claimantName': claimantName.trim(),
      'claimantPhone': claimantPhone,
      'reportItemName': reportItemName,
      'message': message.trim(),
      'verificationDetails': verificationDetails.trim(),
      'status': ClaimStatus.pending.value,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// The reviewer's change (approve / reject / complete). The matching change
  /// to the report must be in the SAME batch (see ClaimService).
  static Map<String, dynamic> reviewMap({
    required ClaimStatus status,
    required String reviewerUid,
    String note = '',
  }) {
    final map = <String, dynamic>{
      'status': status.value,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': reviewerUid,
    };
    final cleanNote = note.trim();
    if (cleanNote.isNotEmpty) {
      map['reviewNote'] = cleanNote;
    }
    if (status == ClaimStatus.completed) {
      map['completedAt'] = FieldValue.serverTimestamp();
    }
    return map;
  }
}
