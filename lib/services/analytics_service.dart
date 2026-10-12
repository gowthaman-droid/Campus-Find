import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/enums.dart';
import '../models/stats.dart';
import '../utils/constants.dart';
import '../utils/firestore_count.dart';

/// Real numbers for the admin dashboard and the analytics screen.
///
/// Everything is counted by Firestore itself (`count()` queries), so nothing
/// is hard-coded and the app does not download the reports to count them.
/// Only admins may run these queries (the security rules refuse everybody
/// else). Category and campus-area numbers use the fixed lists in
/// AppConstants, so each one is a plain equality count.
class AnalyticsService {
  AnalyticsService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection(FirestorePaths.users);
  CollectionReference<Map<String, dynamic>> get _reports =>
      _db.collection(FirestorePaths.reports);
  CollectionReference<Map<String, dynamic>> get _claims =>
      _db.collection(FirestorePaths.claims);
  CollectionReference<Map<String, dynamic>> get _matches =>
      _db.collection(FirestorePaths.matches);

  /// The six numbers on the admin dashboard.
  Future<AdminStats> loadAdminStats() async {
    final counts = await Future.wait<int>(<Future<int>>[
      countDocuments(_users),
      countDocuments(_reports.where('type', isEqualTo: ReportType.lost.value)),
      countDocuments(_reports.where('type', isEqualTo: ReportType.found.value)),
      countDocuments(
        _claims.where('status', isEqualTo: ClaimStatus.pending.value),
      ),
      countDocuments(
        _reports.where('status', isEqualTo: ReportStatus.returned.value),
      ),
      countDocuments(
        _matches.where('status', isEqualTo: MatchRecordStatus.active.value),
      ),
    ]);
    return AdminStats(
      totalUsers: counts[0],
      totalLostReports: counts[1],
      totalFoundReports: counts[2],
      pendingClaims: counts[3],
      returnedItems: counts[4],
      activeMatches: counts[5],
    );
  }

  /// Everything on the analytics screen.
  Future<AnalyticsSummary> loadSummary() async {
    final totals = await Future.wait<int>(<Future<int>>[
      countDocuments(_reports),
      countDocuments(_reports.where('type', isEqualTo: ReportType.lost.value)),
      countDocuments(_reports.where('type', isEqualTo: ReportType.found.value)),
      countDocuments(
        _reports.where('status', isEqualTo: ReportStatus.returned.value),
      ),
      countDocuments(
        _claims.where('status', isEqualTo: ClaimStatus.pending.value),
      ),
      countDocuments(
        _matches.where('status', isEqualTo: MatchRecordStatus.resolved.value),
      ),
    ]);
    final byCategory = await _countByValue('category', AppConstants.categories);
    final byLocation = await _countByValue('location', AppConstants.locations);

    return AnalyticsSummary(
      totalReports: totals[0],
      lostReports: totals[1],
      foundReports: totals[2],
      returnedItems: totals[3],
      pendingClaims: totals[4],
      successfulMatches: totals[5],
      byCategory: byCategory,
      byLocation: byLocation,
      generatedAt: DateTime.now(),
    );
  }

  /// How many reports have each of the [values] in [field].
  Future<Map<String, int>> _countByValue(
    String field,
    List<String> values,
  ) async {
    final counts = await Future.wait<int>(
      values.map(
        (value) => countDocuments(_reports.where(field, isEqualTo: value)),
      ),
    );
    return <String, int>{
      for (var i = 0; i < values.length; i++) values[i]: counts[i],
    };
  }
}
