import 'package:campus_find/models/report.dart';
import 'package:campus_find/services/report_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Report makeReport(String id, List<String> keywords, DateTime createdAt) {
  return Report.fromMap(id, <String, dynamic>{
    'itemName': id,
    'keywords': keywords,
    'createdAt': Timestamp.fromDate(createdAt),
  });
}

void main() {
  final tokens = <String>['black', 'wallet'];
  final bothWords = makeReport('both', <String>['black', 'wallet', 'library'], DateTime(2026, 10, 1));
  final oneWord = makeReport('one', <String>['black'], DateTime(2026, 10, 2));
  final noWord = makeReport('none', <String>['blue'], DateTime(2026, 10, 3));

  test('relevanceOf counts the searched words a report contains', () {
    expect(ReportService.relevanceOf(bothWords, tokens), 2);
    expect(ReportService.relevanceOf(oneWord, tokens), 1);
    expect(ReportService.relevanceOf(noWord, tokens), 0);
  });

  test('rankByRelevance puts the best match first', () {
    final ranked = ReportService.rankByRelevance(
      <Report>[noWord, oneWord, bothWords],
      tokens,
    );
    expect(ranked.map((r) => r.id).toList(), <String>['both', 'one', 'none']);
  });

  test('equal scores keep the newest report first', () {
    final older = makeReport('older', <String>['black'], DateTime(2026, 9, 1));
    final newer = makeReport('newer', <String>['black'], DateTime(2026, 9, 20));
    final ranked = ReportService.rankByRelevance(<Report>[older, newer], tokens);
    expect(ranked.map((r) => r.id).toList(), <String>['newer', 'older']);
  });

  test('without search words the order is unchanged', () {
    final input = <Report>[noWord, oneWord, bothWords];
    final ranked = ReportService.rankByRelevance(input, const <String>[]);
    expect(ranked.map((r) => r.id).toList(), <String>['none', 'one', 'both']);
    expect(identical(ranked, input), isFalse);
  });
}
