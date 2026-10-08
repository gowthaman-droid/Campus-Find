import 'package:campus_find/models/claim.dart';
import 'package:campus_find/models/enums.dart';
import 'package:campus_find/models/match_result.dart';
import 'package:campus_find/models/report.dart';
import 'package:campus_find/models/search_filters.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Report.fromMap', () {
    test('reads every field', () {
      final report = Report.fromMap('r1', <String, dynamic>{
        'type': 'found',
        'userId': 'u1',
        'reporterName': 'Asha K',
        'itemName': 'Blue bottle',
        'category': 'Other',
        'description': 'Steel bottle with a dent',
        'additionalDetails': '',
        'location': 'Library',
        'locationDetail': '2nd floor',
        'eventAt': Timestamp.fromDate(DateTime.utc(2026, 10, 6, 10, 30)),
        'imageUrl': '',
        'imagePath': '',
        'status': 'claimed',
        'hidden': false,
        'matchStatus': 'done',
        'keywords': <String>['blue', 'bottle'],
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 10, 6, 10, 41)),
        'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 10, 6, 10, 42)),
        'matchCount': 2,
        'bestMatchScore': 87,
      });
      expect(report.id, 'r1');
      expect(report.type, ReportType.found);
      expect(report.isFound, isTrue);
      expect(report.isClaimed, isTrue);
      expect(report.matchStatus, MatchState.done);
      expect(report.locationLabel, 'Library - 2nd floor');
      expect(report.eventAt.toUtc(), DateTime.utc(2026, 10, 6, 10, 30));
      expect(report.bestMatchScore, 87);
      expect(report.hasImage, isFalse);
      expect(report.isOwnedBy('u1'), isTrue);
      expect(report.isOwnedBy('u2'), isFalse);
    });

    test('uses safe defaults for missing fields', () {
      final report = Report.fromMap('x', <String, dynamic>{});
      expect(report.itemName, '');
      expect(report.type, ReportType.lost);
      expect(report.status, ReportStatus.active);
      expect(report.matchCount, 0);
      expect(report.keywords, isEmpty);
    });
  });

  group('Claim', () {
    test('document id is reportId_claimantUid', () {
      expect(Claim.idFor('rep1', 'uidA'), 'rep1_uidA');
    });

    test('fromMap and the helper getters', () {
      final claim = Claim.fromMap('rep1_uidA', <String, dynamic>{
        'reportId': 'rep1',
        'reportOwnerId': 'owner',
        'claimantId': 'uidA',
        'claimantName': 'Ravi',
        'claimantPhone': '9876543210',
        'reportItemName': 'Wallet',
        'message': 'It is my wallet',
        'verificationDetails': 'Has a bus pass',
        'status': 'approved',
      });
      expect(claim.status, ClaimStatus.approved);
      expect(claim.isOpen, isTrue);
      expect(claim.revealsContact, isTrue);
      expect(claim.isPending, isFalse);
    });
  });

  group('MatchResponse.fromJson', () {
    test('reads the example from docs/API.md', () {
      final response = MatchResponse.fromJson(<String, dynamic>{
        'report_id': 'k3J9',
        'match': true,
        'score': 87,
        'matched_report_id': 'abc123',
        'matches': <dynamic>[
          <String, dynamic>{
            'match_id': 'k3J9_abc123',
            'matched_report_id': 'abc123',
            'score': 87,
            'strong': true,
            'breakdown': <String, dynamic>{
              'name': 92,
              'location': 100,
              'category': 100,
              'description': 61,
              'time': 88,
            },
          },
        ],
        'evaluated': 14,
        'created': 1,
        'updated': 0,
        'notified': 2,
      });
      expect(response.match, isTrue);
      expect(response.score, 87);
      expect(response.matchedReportId, 'abc123');
      expect(response.hasStrongMatch, isTrue);
      expect(response.matches.single.breakdown.location, 100);
      expect(response.matches.single.breakdown.rows.length, 5);
      expect(response.notified, 2);
    });

    test('no match', () {
      final response = MatchResponse.fromJson(<String, dynamic>{
        'report_id': 'k3J9',
        'match': false,
        'score': 0,
        'matched_report_id': null,
        'matches': <dynamic>[],
      });
      expect(response.match, isFalse);
      expect(response.matchedReportId, isNull);
      expect(response.matches, isEmpty);
    });
  });

  group('SearchFilters', () {
    test('empty by default and equal when the same', () {
      const a = SearchFilters();
      const b = SearchFilters();
      expect(a.isEmpty, isTrue);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith sets and clears values', () {
      const start = SearchFilters(query: 'black wallet');
      final withType = start.copyWith(type: ReportType.lost);
      expect(withType.type, ReportType.lost);
      expect(withType.isEmpty, isFalse);
      expect(withType.activeFilterCount, 1);
      expect(withType.tokens, <String>['black', 'wallet']);

      final cleared = withType.copyWith(clearType: true);
      expect(cleared.type, isNull);
      expect(cleared.activeFilterCount, 0);
    });
  });

  group('enums', () {
    test('unknown text falls back to a safe value', () {
      expect(ReportStatus.fromValue('nonsense'), ReportStatus.active);
      expect(ClaimStatus.fromValue(null), ClaimStatus.pending);
      expect(NotificationType.fromValue('new_kind'), NotificationType.unknown);
    });

    test('opposite report type', () {
      expect(ReportType.lost.opposite, ReportType.found);
      expect(ReportType.found.opposite, ReportType.lost);
    });
  });
}
