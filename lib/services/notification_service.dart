import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification.dart';
import '../utils/constants.dart';
import '../utils/firestore_write.dart';

/// The in-app notification list: `notifications/{id}`.
///
/// Notifications are CREATED by the Python service only. A person can read
/// their own, mark them as read and delete them. (Push messages to the phone
/// are handled by the FCM service in Phase 18.)
class NotificationService {
  NotificationService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _notifications =>
      _db.collection(FirestorePaths.notifications);

  /// My notifications, newest first.
  Stream<List<AppNotification>> watchMine(String uid, {int limit = 50}) {
    return _notifications
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(AppNotification.fromDoc).toList());
  }

  /// Number of unread notifications for the bell badge. Counts up to 99;
  /// show "99+" when the number is 99.
  Stream<int> watchUnreadCount(String uid) {
    return _notifications
        .where('userId', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .limit(99)
        .snapshots()
        .map((snapshot) => snapshot.size);
  }

  Future<void> markRead(String id, {bool read = true}) async {
    await waitForServer(
      _notifications.doc(id).update(AppNotification.readUpdateMap(read)),
      label: 'mark notification',
    );
  }

  /// Marks all my unread notifications as read. Returns how many changed.
  Future<int> markAllRead(String uid) async {
    final snapshot = await _notifications
        .where('userId', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .limit(400)
        .get();
    if (snapshot.docs.isEmpty) {
      return 0;
    }
    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, AppNotification.readUpdateMap(true));
    }
    await waitForServer(batch.commit(), label: 'mark all read');
    return snapshot.docs.length;
  }

  Future<void> delete(String id) async {
    await waitForServer(_notifications.doc(id).delete(), label: 'delete notification');
  }

  /// Deletes up to 400 of my notifications. Returns how many were removed.
  Future<int> deleteAllMine(String uid) async {
    final snapshot = await _notifications
        .where('userId', isEqualTo: uid)
        .limit(400)
        .get();
    if (snapshot.docs.isEmpty) {
      return 0;
    }
    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await waitForServer(batch.commit(), label: 'clear notifications');
    return snapshot.docs.length;
  }

  /// Admin only: the latest notifications of everybody.
  Stream<List<AppNotification>> watchAll({int limit = 100}) {
    return _notifications
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(AppNotification.fromDoc).toList());
  }
}
