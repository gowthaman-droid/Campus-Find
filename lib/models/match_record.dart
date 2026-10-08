import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/parsers.dart';
import 'enums.dart';
import 'match_result.dart';

/// A stored match between one lost and one found report:
/// the document `matches/{lostReportId}_{foundReportId}`.
/// Written by the Python service only; the app just reads it.
class MatchRecord {
  const MatchRecord({
    required this.id,
    required this.lostReportId,
    required this.foundReportId,
    required this.lostUserId,
    required this.foundUserId,
    required this.participants,
    required this.lostItemName,
    required this.foundItemName,
    required this.score,
    required this.strong,
    required this.breakdown,
    required this.status,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String lostReportId;
  final String foundReportId;
  final String lostUserId;
  final String foundUserId;

  /// [lostUserId, foundUserId]; lets one query find all matches of a person.
  final List<String> participants;

  final String lostItemName;
  final String foundItemName;
  final int score;
  final bool strong;
  final ScoreBreakdown breakdown;
  final MatchRecordStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == MatchRecordStatus.active;

  bool isLostSide(String uid) => uid == lostUserId;

  /// The report that belongs to [uid] in this match.
  String myReportId(String uid) => isLostSide(uid) ? lostReportId : foundReportId;

  /// The other person's report, the one worth opening.
  String otherReportId(String uid) =>
      isLostSide(uid) ? foundReportId : lostReportId;

  String otherItemName(String uid) =>
      isLostSide(uid) ? foundItemName : lostItemName;

  factory MatchRecord.fromMap(String id, Map<String, dynamic> map) {
    return MatchRecord(
      id: id,
      lostReportId: readString(map, 'lostReportId'),
      foundReportId: readString(map, 'foundReportId'),
      lostUserId: readString(map, 'lostUserId'),
      foundUserId: readString(map, 'foundUserId'),
      participants: readStringList(map, 'participants'),
      lostItemName: readString(map, 'lostItemName'),
      foundItemName: readString(map, 'foundItemName'),
      score: readInt(map, 'score'),
      strong: readBool(map, 'strong'),
      breakdown: ScoreBreakdown.fromMap(readMap(map, 'breakdown')),
      status: MatchRecordStatus.fromValue(readString(map, 'status')),
      createdAt: readDateTimeOr(map, 'createdAt', DateTime.now()),
      updatedAt: readDateTime(map, 'updatedAt'),
    );
  }

  factory MatchRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return MatchRecord.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});
  }
}
