import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/parsers.dart';
import 'enums.dart';

/// One entry in a person's notification list: `notifications/{id}`.
/// Created by the Python service only; the person can mark it read or delete it.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.reportId = '',
    this.claimId = '',
    this.matchId = '',
  });

  final String id;
  final String userId;
  final NotificationType type;
  final String title;
  final String body;
  final bool read;
  final DateTime createdAt;

  /// Used to open the right screen when the notification is tapped.
  final String reportId;
  final String claimId;
  final String matchId;

  bool get hasTarget =>
      reportId.isNotEmpty || claimId.isNotEmpty || matchId.isNotEmpty;

  factory AppNotification.fromMap(String id, Map<String, dynamic> map) {
    return AppNotification(
      id: id,
      userId: readString(map, 'userId'),
      type: NotificationType.fromValue(readString(map, 'type')),
      title: readString(map, 'title'),
      body: readString(map, 'body'),
      read: readBool(map, 'read'),
      createdAt: readDateTimeOr(map, 'createdAt', DateTime.now()),
      reportId: readString(map, 'reportId'),
      claimId: readString(map, 'claimId'),
      matchId: readString(map, 'matchId'),
    );
  }

  factory AppNotification.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AppNotification.fromMap(
      doc.id,
      doc.data() ?? const <String, dynamic>{},
    );
  }

  /// The only change the rules let a person make to a notification.
  static Map<String, dynamic> readUpdateMap(bool read) {
    return <String, dynamic>{'read': read};
  }
}
