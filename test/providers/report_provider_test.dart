import 'dart:async';

import 'package:campus_find/models/app_user.dart';
import 'package:campus_find/models/enums.dart';
import 'package:campus_find/models/match_result.dart';
import 'package:campus_find/models/report.dart';
import 'package:campus_find/models/report_draft.dart';
import 'package:campus_find/providers/report_provider.dart';
import 'package:campus_find/services/match_service.dart';
import 'package:campus_find/services/report_service.dart';
import 'package:campus_find/utils/app_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockReportService extends Mock implements ReportService {}

class MockMatchService extends Mock implements MatchService {}

final AppUser profile = AppUser(
  uid: 'u1',
  name: 'Asha Kumar',
  email: 'asha@college.edu',
  phone: '9876543210',
  role: UserRole.student,
  createdAt: DateTime(2026, 10, 1),
);

final ReportDraft draft = ReportDraft(
  type: ReportType.lost,
  itemName: 'Black leather wallet',
  category: 'Wallets & Purses',
  description: 'Brown stitching, college ID inside',
  location: 'Library',
  eventAt: DateTime(2026, 10, 6, 9, 30),
);

Report makeReport(String id) {
  return Report.fromMap(id, <String, dynamic>{'itemName': id, 'userId': 'u1'});
}

MatchOutcome outcomeWithMatches(int count) {
  final items = List<MatchItem>.generate(
    count,
    (i) => MatchItem(
      matchId: 'r1_f$i',
      matchedReportId: 'f$i',
      score: 80,
      strong: true,
      breakdown: const ScoreBreakdown(),
    ),
  );
  return MatchOutcome.done(
    MatchResponse(
      reportId: 'r1',
      match: count > 0,
      score: count > 0 ? 80 : 0,
      matches: items,
    ),
  );
}

void main() {
  late MockReportService reports;
  late MockMatchService matches;

  setUpAll(() {
    registerFallbackValue(profile);
    registerFallbackValue(draft);
    registerFallbackValue(makeReport('fallback'));
  });

  setUp(() {
    reports = MockReportService();
    matches = MockMatchService();
    when(() => reports.watchMyReports(any()))
        .thenAnswer((_) => Stream<List<Report>>.value(<Report>[]));
    when(() => matches.retryPending(any())).thenAnswer((_) async => 0);
  });

  ReportProvider makeProvider() {
    return ReportProvider(reports: reports, matches: matches);
  }

  void stubCreate({bool synced = true}) {
    when(
      () => reports.createReport(
        reporter: any(named: 'reporter'),
        draft: any(named: 'draft'),
        onUploadProgress: any(named: 'onUploadProgress'),
      ),
    ).thenAnswer(
      (_) async => CreateReportResult(reportId: 'r1', synced: synced),
    );
  }

  group('following the signed-in person', () {
    test('shows my reports live and clears them when I log out', () async {
      when(() => reports.watchMyReports(any())).thenAnswer(
        (_) => Stream<List<Report>>.value(<Report>[makeReport('r1')]),
      );
      final provider = makeProvider();

      provider.bindUser(profile);
      await pumpEventQueue();

      expect(provider.myReports.map((r) => r.id).toList(), <String>['r1']);
      expect(provider.loading, isFalse);
      expect(provider.byId('r1'), isNotNull);
      verify(() => matches.retryPending('u1')).called(1);

      provider.bindUser(null);
      await pumpEventQueue();

      expect(provider.myReports, isEmpty);
      provider.dispose();
    });

    test('does not restart the listener when the same person is bound again', () async {
      final provider = makeProvider();

      provider.bindUser(profile);
      provider.bindUser(profile);
      await pumpEventQueue();

      verify(() => reports.watchMyReports(any())).called(1);
      provider.dispose();
    });
  });

  group('submitReport', () {
    test('saves the report and then runs the matching', () async {
      stubCreate();
      when(() => matches.runMatching(any()))
          .thenAnswer((_) async => outcomeWithMatches(1));
      final provider = makeProvider();
      provider.bindUser(profile);

      final result = await provider.submitReport(draft);

      expect(result.success, isTrue);
      expect(result.isWarning, isFalse);
      expect(result.data?.reportId, 'r1');
      expect(result.data?.matchCount, 1);
      expect(result.message, contains('1 possible match'));
      expect(provider.saving, isFalse);
      verify(() => matches.runMatching('r1')).called(1);
      provider.dispose();
    });

    test('offline: the report is kept and matching is not tried yet', () async {
      stubCreate(synced: false);
      final provider = makeProvider();
      provider.bindUser(profile);

      final result = await provider.submitReport(draft);

      expect(result.success, isTrue);
      expect(result.isWarning, isTrue);
      expect(result.message, contains('offline'));
      verifyNever(() => matches.runMatching(any()));
      provider.dispose();
    });

    test('a failed matching never makes the saved report look like a failure', () async {
      stubCreate();
      when(() => matches.runMatching(any())).thenAnswer(
        (_) async => MatchOutcome.failed('service not reachable'),
      );
      final provider = makeProvider();
      provider.bindUser(profile);

      final result = await provider.submitReport(draft);

      expect(result.success, isTrue);
      expect(result.isWarning, isTrue);
      expect(result.message, contains('tried again'));
      provider.dispose();
    });

    test('an unexpected matching error does not fail the submit either', () async {
      stubCreate();
      when(() => matches.runMatching(any()))
          .thenThrow(const ApiException('Bad request', statusCode: 400));
      final provider = makeProvider();
      provider.bindUser(profile);

      final result = await provider.submitReport(draft);

      expect(result.success, isTrue);
      expect(result.message, 'Your report was saved.');
      provider.dispose();
    });

    test('a problem while saving becomes a friendly failure', () async {
      when(
        () => reports.createReport(
          reporter: any(named: 'reporter'),
          draft: any(named: 'draft'),
          onUploadProgress: any(named: 'onUploadProgress'),
        ),
      ).thenThrow(const AppException('Please add your phone number.'));
      final provider = makeProvider();
      provider.bindUser(profile);

      final result = await provider.submitReport(draft);

      expect(result.success, isFalse);
      expect(result.message, 'Please add your phone number.');
      expect(provider.saving, isFalse);
      verifyNever(() => matches.runMatching(any()));
      provider.dispose();
    });

    test('needs a signed-in person', () async {
      final provider = makeProvider();

      final result = await provider.submitReport(draft);

      expect(result.success, isFalse);
      expect(result.message, 'Please log in first.');
      verifyNever(
        () => reports.createReport(
          reporter: any(named: 'reporter'),
          draft: any(named: 'draft'),
          onUploadProgress: any(named: 'onUploadProgress'),
        ),
      );
      provider.dispose();
    });

    test('a second tap while saving is refused', () async {
      final gate = Completer<CreateReportResult>();
      when(
        () => reports.createReport(
          reporter: any(named: 'reporter'),
          draft: any(named: 'draft'),
          onUploadProgress: any(named: 'onUploadProgress'),
        ),
      ).thenAnswer((_) => gate.future);
      when(() => matches.runMatching(any()))
          .thenAnswer((_) async => outcomeWithMatches(0));
      final provider = makeProvider();
      provider.bindUser(profile);

      final first = provider.submitReport(draft);
      await pumpEventQueue();
      expect(provider.saving, isTrue);

      final second = await provider.submitReport(draft);
      expect(second.success, isFalse);

      gate.complete(const CreateReportResult(reportId: 'r1', synced: true));
      expect((await first).success, isTrue);
      provider.dispose();
    });
  });

  group('other actions', () {
    test('retryMatching reports how many matches were found', () async {
      when(() => matches.runMatching(any()))
          .thenAnswer((_) async => outcomeWithMatches(2));
      final provider = makeProvider();

      final result = await provider.retryMatching('r1');

      expect(result.success, isTrue);
      expect(result.message, 'We found 2 possible matches!');
      provider.dispose();
    });

    test('markReturned passes my id and the name of the receiver', () async {
      when(
        () => reports.markReturned(
          report: any(named: 'report'),
          userId: any(named: 'userId'),
          returnedTo: any(named: 'returnedTo'),
        ),
      ).thenAnswer((_) async => true);
      final provider = makeProvider();
      provider.bindUser(profile);
      final report = makeReport('r1');

      final result = await provider.markReturned(report, 'Ravi');

      expect(result.success, isTrue);
      expect(result.isWarning, isFalse);
      verify(
        () => reports.markReturned(
          report: report,
          userId: 'u1',
          returnedTo: 'Ravi',
        ),
      ).called(1);
      provider.dispose();
    });

    test('deleteReport reports an offline deletion as a warning', () async {
      when(
        () => reports.deleteReport(
          any(),
          actorUid: any(named: 'actorUid'),
        ),
      ).thenAnswer((_) async => false);
      final provider = makeProvider();
      provider.bindUser(profile);

      final result = await provider.deleteReport(makeReport('r1'));

      expect(result.success, isTrue);
      expect(result.isWarning, isTrue);
      provider.dispose();
    });
  });

  test('pendingMatchCount counts active reports that were not matched yet', () async {
    when(() => reports.watchMyReports(any())).thenAnswer(
      (_) => Stream<List<Report>>.value(<Report>[
        Report.fromMap('a', <String, dynamic>{'matchStatus': 'pending'}),
        Report.fromMap('b', <String, dynamic>{'matchStatus': 'done'}),
        Report.fromMap('c', <String, dynamic>{'matchStatus': 'failed'}),
        Report.fromMap(
          'd',
          <String, dynamic>{'matchStatus': 'pending', 'status': 'returned'},
        ),
      ]),
    );
    final provider = makeProvider();

    provider.bindUser(profile);
    await pumpEventQueue();

    expect(provider.pendingMatchCount, 2);
    provider.dispose();
  });
}
