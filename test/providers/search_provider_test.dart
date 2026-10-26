import 'dart:async';

import 'package:campus_find/models/enums.dart';
import 'package:campus_find/models/report.dart';
import 'package:campus_find/models/search_filters.dart';
import 'package:campus_find/providers/search_provider.dart';
import 'package:campus_find/services/report_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockReportService extends Mock implements ReportService {}

Report makeReport(
  String id, {
  List<String> keywords = const <String>[],
  DateTime? createdAt,
}) {
  return Report.fromMap(id, <String, dynamic>{
    'itemName': id,
    'keywords': keywords,
    'createdAt': Timestamp.fromDate(createdAt ?? DateTime(2026, 10, 1)),
  });
}

ReportPage pageOf(
  List<Report> items, {
  bool hasMore = false,
  DocumentSnapshot<Map<String, dynamic>>? cursor,
}) {
  return ReportPage(items: items, cursor: cursor, hasMore: hasMore);
}

List<String> idsOf(SearchProvider provider) =>
    provider.results.map((report) => report.id).toList();

void main() {
  late MockReportService reports;
  late DocumentSnapshot<Map<String, dynamic>> cursor;

  setUpAll(() {
    registerFallbackValue(const SearchFilters());
  });

  setUp(() async {
    reports = MockReportService();
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('cursors').doc('c1').set(<String, dynamic>{
      'position': 1,
    });
    cursor = await firestore.collection('cursors').doc('c1').get();
  });

  test('ensureLoaded loads the first page once', () async {
    when(() => reports.fetchPage(any())).thenAnswer(
      (_) async => pageOf(
        <Report>[makeReport('r1'), makeReport('r2')],
        hasMore: true,
        cursor: cursor,
      ),
    );
    final provider = SearchProvider(reports: reports);
    provider.bindUser('u1');

    await provider.ensureLoaded();
    await provider.ensureLoaded();

    expect(idsOf(provider), <String>['r1', 'r2']);
    expect(provider.hasMore, isTrue);
    expect(provider.loading, isFalse);
    verify(() => reports.fetchPage(any())).called(1);
    provider.dispose();
  });

  test('does nothing when nobody is signed in', () async {
    final provider = SearchProvider(reports: reports);

    await provider.ensureLoaded();
    await provider.search();

    verifyNever(() => reports.fetchPage(any()));
    provider.dispose();
  });

  test('loadMore adds the next page and skips duplicates', () async {
    when(() => reports.fetchPage(any())).thenAnswer(
      (_) async => pageOf(
        <Report>[makeReport('r1'), makeReport('r2')],
        hasMore: true,
        cursor: cursor,
      ),
    );
    when(() => reports.fetchPage(any(), startAfter: cursor)).thenAnswer(
      (_) async => pageOf(
        <Report>[makeReport('r2'), makeReport('r3')],
        hasMore: false,
        cursor: cursor,
      ),
    );
    final provider = SearchProvider(reports: reports);
    provider.bindUser('u1');
    provider.addListener(
      () => print(
        'ids=${idsOf(provider)} loading=${provider.loading} more=${provider.loadingMore}',
      ),
    );

    await provider.ensureLoaded();
    expect(idsOf(provider), <String>['r1', 'r2']); // first page only
    expect(provider.hasMore, isTrue);

    await provider.loadMore();

    expect(idsOf(provider), <String>['r1', 'r2', 'r3']);
    expect(provider.hasMore, isFalse);
    expect(provider.loadingMore, isFalse);
    verify(() => reports.fetchPage(any(), startAfter: cursor)).called(1);
    provider.dispose();
  });
  test(
    'a changed filter starts a new search and the old answer is ignored',
    () async {
      final slowFirst = Completer<ReportPage>();
      var calls = 0;
      when(() => reports.fetchPage(any())).thenAnswer((_) {
        calls++;
        if (calls == 1) {
          return slowFirst.future;
        }
        return Future<ReportPage>.value(pageOf(<Report>[makeReport('new')]));
      });
      final provider = SearchProvider(reports: reports);
      provider.bindUser('u1');

      final first = provider.search();
      provider.setType(ReportType.lost);
      await pumpEventQueue();
      expect(idsOf(provider), <String>['new']);

      slowFirst.complete(pageOf(<Report>[makeReport('old')]));
      await first;
      await pumpEventQueue();

      expect(idsOf(provider), <String>['new']);
      expect(provider.filters.type, ReportType.lost);
      expect(provider.loading, isFalse);
      provider.dispose();
    },
  );

  test('a failed search shows a friendly message', () async {
    when(() => reports.fetchPage(any())).thenThrow(
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
    );
    final provider = SearchProvider(reports: reports);
    provider.bindUser('u1');

    await provider.search();

    expect(provider.error, contains('Cannot reach'));
    expect(provider.results, isEmpty);
    expect(provider.loading, isFalse);
    provider.dispose();
  });

  test('typing waits for the debounce before searching', () async {
    when(
      () => reports.fetchPage(any()),
    ).thenAnswer((_) async => pageOf(<Report>[]));
    final provider = SearchProvider(
      reports: reports,
      debounce: const Duration(milliseconds: 20),
    );
    provider.bindUser('u1');

    provider.setText('black wallet');
    verifyNever(() => reports.fetchPage(any()));

    await Future<void>.delayed(const Duration(milliseconds: 120));

    verify(() => reports.fetchPage(any())).called(1);
    expect(provider.filters.query, 'black wallet');
    provider.dispose();
  });

  test('results are ranked by how many typed words they contain', () async {
    final one = makeReport(
      'one',
      keywords: <String>['black'],
      createdAt: DateTime(2026, 10, 2),
    );
    final both = makeReport(
      'both',
      keywords: <String>['black', 'wallet'],
      createdAt: DateTime(2026, 10, 1),
    );
    when(
      () => reports.fetchPage(any()),
    ).thenAnswer((_) async => pageOf(<Report>[one, both]));
    final provider = SearchProvider(reports: reports);
    provider.bindUser('u1');
    provider.setText('black wallet');

    await provider.search();

    expect(idsOf(provider), <String>['both', 'one']);
    provider.dispose();
  });

  test('an empty answer shows the empty state', () async {
    when(
      () => reports.fetchPage(any()),
    ).thenAnswer((_) async => pageOf(<Report>[]));
    final provider = SearchProvider(reports: reports);
    provider.bindUser('u1');

    expect(provider.showsEmptyState, isFalse);
    await provider.search();

    expect(provider.showsEmptyState, isTrue);
    provider.dispose();
  });

  test('a different person starts with a clean slate', () async {
    when(() => reports.fetchPage(any())).thenAnswer(
      (_) async => pageOf(<Report>[makeReport('r1')], cursor: cursor),
    );
    final provider = SearchProvider(reports: reports);
    provider.bindUser('u1');
    provider.setType(ReportType.found);
    await provider.search();
    expect(idsOf(provider), isNotEmpty);

    provider.bindUser('u2');

    expect(provider.results, isEmpty);
    expect(provider.filters.isEmpty, isTrue);
    expect(provider.showsEmptyState, isFalse);
    provider.dispose();
  });
}
