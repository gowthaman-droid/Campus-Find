import 'package:campus_find/models/app_notification.dart';
import 'package:campus_find/models/enums.dart';
import 'package:campus_find/models/match_record.dart';
import 'package:campus_find/providers/dashboard_provider.dart';
import 'package:campus_find/providers/match_provider.dart';
import 'package:campus_find/providers/notification_provider.dart';
import 'package:campus_find/services/match_service.dart';
import 'package:campus_find/services/notification_service.dart';
import 'package:campus_find/services/report_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockNotificationService extends Mock implements NotificationService {}

class MockMatchService extends Mock implements MatchService {}

class MockReportService extends Mock implements ReportService {}

AppNotification makeNotification(String id, {bool read = false}) {
  return AppNotification.fromMap(id, <String, dynamic>{
    'userId': 'u1',
    'type': 'match_found',
    'title': 'Potential match',
    'body': 'Check your reports',
    'read': read,
    'createdAt': Timestamp.fromDate(DateTime(2026, 10, 6)),
  });
}

MatchRecord makeMatch(String id, String lostId, String foundId, int score) {
  return MatchRecord.fromMap(id, <String, dynamic>{
    'lostReportId': lostId,
    'foundReportId': foundId,
    'lostUserId': 'u1',
    'foundUserId': 'u2',
    'participants': <String>['u1', 'u2'],
    'lostItemName': 'Wallet',
    'foundItemName': 'Wallet',
    'score': score,
    'strong': score >= 70,
    'status': 'active',
    'createdAt': Timestamp.fromDate(DateTime(2026, 10, 6)),
  });
}

void main() {
  group('NotificationProvider', () {
    late MockNotificationService service;

    setUp(() {
      service = MockNotificationService();
      when(() => service.watchMine(any())).thenAnswer(
        (_) => Stream<List<AppNotification>>.value(<AppNotification>[
          makeNotification('n1'),
          makeNotification('n2', read: true),
        ]),
      );
      when(() => service.watchUnreadCount(any()))
          .thenAnswer((_) => Stream<int>.value(1));
    });

    test('shows the list and the unread badge', () async {
      final provider = NotificationProvider(notifications: service);

      provider.bindUser('u1');
      await pumpEventQueue();

      expect(provider.items.length, 2);
      expect(provider.unreadCount, 1);
      expect(provider.unreadLabel, '1');
      expect(provider.hasUnread, isTrue);
      expect(provider.loading, isFalse);
      provider.dispose();
    });

    test('the badge shows 99+ from 99 unread notifications', () async {
      when(() => service.watchUnreadCount(any()))
          .thenAnswer((_) => Stream<int>.value(99));
      final provider = NotificationProvider(notifications: service);

      provider.bindUser('u1');
      await pumpEventQueue();

      expect(provider.unreadLabel, '99+');
      provider.dispose();
    });

    test('markRead only calls the service for unread notifications', () async {
      when(() => service.markRead(any())).thenAnswer((_) async {});
      final provider = NotificationProvider(notifications: service);

      final unread = await provider.markRead(makeNotification('n1'));
      final alreadyRead =
          await provider.markRead(makeNotification('n2', read: true));

      expect(unread.success, isTrue);
      expect(alreadyRead.success, isTrue);
      verify(() => service.markRead('n1')).called(1);
      verifyNever(() => service.markRead('n2'));
      provider.dispose();
    });

    test('markAllRead needs a signed-in person and uses their id', () async {
      when(() => service.markAllRead(any())).thenAnswer((_) async => 3);
      final provider = NotificationProvider(notifications: service);

      final signedOut = await provider.markAllRead();
      expect(signedOut.success, isFalse);

      provider.bindUser('u1');
      final result = await provider.markAllRead();

      expect(result.success, isTrue);
      verify(() => service.markAllRead('u1')).called(1);
      provider.dispose();
    });

    test('errors become friendly messages', () async {
      when(() => service.markRead(any())).thenThrow(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      final provider = NotificationProvider(notifications: service);

      final result = await provider.markRead(makeNotification('n1'));

      expect(result.success, isFalse);
      expect(result.message, 'You do not have permission to do that.');
      provider.dispose();
    });
  });

  group('MatchProvider', () {
    test('lists my matches and finds the best score of a report', () async {
      final service = MockMatchService();
      when(() => service.watchMyMatches(any())).thenAnswer(
        (_) => Stream<List<MatchRecord>>.value(<MatchRecord>[
          makeMatch('l1_f1', 'l1', 'f1', 60),
          makeMatch('l2_f1', 'l2', 'f1', 85),
          makeMatch('l3_f3', 'l3', 'f3', 40),
        ]),
      );
      final provider = MatchProvider(matches: service);

      provider.bindUser('u1');
      await pumpEventQueue();

      expect(provider.count, 3);
      expect(provider.hasStrongMatch, isTrue);
      expect(
        provider.forReport('f1').map((match) => match.score).toList(),
        <int>[85, 60],
      );
      expect(provider.bestScoreFor('f1'), 85);
      expect(provider.bestScoreFor('unknown'), 0);
      provider.dispose();
    });

    test('is empty again after logging out', () async {
      final service = MockMatchService();
      when(() => service.watchMyMatches(any())).thenAnswer(
        (_) => Stream<List<MatchRecord>>.value(
          <MatchRecord>[makeMatch('l1_f1', 'l1', 'f1', 60)],
        ),
      );
      final provider = MatchProvider(matches: service);
      provider.bindUser('u1');
      await pumpEventQueue();
      expect(provider.count, 1);

      provider.bindUser(null);

      expect(provider.matches, isEmpty);
      provider.dispose();
    });
  });

  group('DashboardProvider', () {
    late MockReportService reports;
    late MockMatchService matches;

    setUp(() {
      reports = MockReportService();
      matches = MockMatchService();
      when(
        () => reports.countVisible(
          type: ReportType.lost,
          status: ReportStatus.active,
        ),
      ).thenAnswer((_) async => 5);
      when(
        () => reports.countVisible(
          type: ReportType.found,
          status: ReportStatus.active,
        ),
      ).thenAnswer((_) async => 3);
      when(() => reports.countVisible(status: ReportStatus.returned))
          .thenAnswer((_) async => 7);
      when(() => matches.countMyActive('u1')).thenAnswer((_) async => 2);
    });

    test('loads the four real numbers', () async {
      final provider = DashboardProvider(reports: reports, matches: matches);
      provider.bindUser('u1');

      await provider.refresh();

      expect(provider.stats.lostItems, 5);
      expect(provider.stats.foundItems, 3);
      expect(provider.stats.returnedItems, 7);
      expect(provider.stats.potentialMatches, 2);
      expect(provider.loading, isFalse);
      expect(provider.error, isNull);
      provider.dispose();
    });

    test('a failing count shows a friendly message and keeps the old numbers', () async {
      final provider = DashboardProvider(reports: reports, matches: matches);
      provider.bindUser('u1');
      await provider.refresh();

      when(() => matches.countMyActive('u1')).thenAnswer(
        (_) async => throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
        ),
      );
      await provider.refresh();

      expect(provider.error, contains('Cannot reach'));
      expect(provider.stats.lostItems, 5);
      expect(provider.loading, isFalse);
      provider.dispose();
    });

    test('does nothing when nobody is signed in', () async {
      final provider = DashboardProvider(reports: reports, matches: matches);

      await provider.refresh();

      verifyNever(() => matches.countMyActive(any()));
      provider.dispose();
    });
  });
}
