import 'package:campus_find/models/enums.dart';
import 'package:campus_find/models/report_draft.dart';
import 'package:flutter_test/flutter_test.dart';

ReportDraft draft({
  String itemName = 'Black leather wallet',
  String category = 'Wallets & Purses',
  String description = 'Brown stitching, college ID inside',
  String location = 'Library',
  String locationDetail = '',
  String additionalDetails = '',
  DateTime? eventAt,
}) {
  return ReportDraft(
    type: ReportType.lost,
    itemName: itemName,
    category: category,
    description: description,
    location: location,
    locationDetail: locationDetail,
    additionalDetails: additionalDetails,
    eventAt: eventAt ?? DateTime(2026, 10, 6, 9, 30),
  );
}

void main() {
  final now = DateTime(2026, 10, 7, 12, 0);

  group('ReportDraft.validate', () {
    test('a complete draft is fine', () {
      expect(draft().validate(now: now), isNull);
    });

    test('item name must be 2 to 100 characters', () {
      expect(draft(itemName: 'a').validate(now: now), contains('Item name'));
      expect(draft(itemName: 'x' * 101).validate(now: now), contains('Item name'));
    });

    test('category and campus area must come from the lists', () {
      expect(draft(category: 'Pets').validate(now: now), contains('category'));
      expect(draft(location: 'Moon').validate(now: now), contains('campus area'));
    });

    test('description needs at least 10 characters', () {
      expect(draft(description: 'too short').validate(now: now), contains('Description'));
    });

    test('long optional texts are limited', () {
      expect(
        draft(locationDetail: 'x' * 121).validate(now: now),
        contains('exact spot'),
      );
      expect(
        draft(additionalDetails: 'x' * 1001).validate(now: now),
        contains('Additional details'),
      );
    });

    test('the date cannot be in the future (5 minutes of clock slack)', () {
      final tomorrow = now.add(const Duration(days: 1));
      final soon = now.add(const Duration(minutes: 3));
      expect(draft(eventAt: tomorrow).validate(now: now), contains('future'));
      expect(draft(eventAt: soon).validate(now: now), isNull);
    });
  });

  test('combine joins the date picker and the time picker', () {
    final combined = ReportDraft.combine(DateTime(2026, 10, 6, 23, 59), 9, 5);
    expect(combined, DateTime(2026, 10, 6, 9, 5));
  });
}
