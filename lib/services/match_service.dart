import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/enums.dart';
import '../models/match_record.dart';
import '../models/match_result.dart';
import '../models/report.dart';
import '../utils/app_exception.dart';
import '../utils/constants.dart';
import '../utils/firestore_write.dart';
import 'backend_api_service.dart';

/// How a call to the matching service ended.
enum MatchOutcomeKind {
  /// The service answered. It may or may not have found matches.
  done,

  /// The service could not be reached. The report is safe; matching was
  /// marked "failed" and will be retried (see [MatchService.retryPending]).
  failed,

  /// The service refused because the report is not eligible any more
  /// (already claimed, returned or hidden). Nothing to retry.
  skipped,
}

class MatchOutcome {
  const MatchOutcome._(this.kind, {this.response, this.message});

  factory MatchOutcome.done(MatchResponse response) {
    return MatchOutcome._(MatchOutcomeKind.done, response: response);
  }

  factory MatchOutcome.failed(String message) {
    return MatchOutcome._(MatchOutcomeKind.failed, message: message);
  }

  factory MatchOutcome.skipped(String message) {
    return MatchOutcome._(MatchOutcomeKind.skipped, message: message);
  }

  final MatchOutcomeKind kind;
  final MatchResponse? response;

  /// A friendly sentence for [MatchOutcomeKind.failed] and [MatchOutcomeKind.skipped].
  final String? message;

  bool get isDone => kind == MatchOutcomeKind.done;
  bool get isFailed => kind == MatchOutcomeKind.failed;
  bool get hasMatch => response?.match ?? false;
  bool get hasStrongMatch => response?.hasStrongMatch ?? false;
}

/// Matching between lost and found reports.
///
/// The score is calculated by the Python service, which writes the records in
/// `matches/{lostId}_{foundId}`. The app only asks for a run ([runMatching])
/// and reads the results.
class MatchService {
  MatchService({
    FirebaseFirestore? firestore,
    required BackendApiService api,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _api = api;

  final FirebaseFirestore _db;
  final BackendApiService _api;

  CollectionReference<Map<String, dynamic>> get _matches =>
      _db.collection(FirestorePaths.matches);

  CollectionReference<Map<String, dynamic>> get _reports =>
      _db.collection(FirestorePaths.reports);

  // ---------------------------------------------------------------------
  // Running the matching
  // ---------------------------------------------------------------------

  /// Asks the Python service to find matches for [reportId].
  ///
  /// A report is never lost because the service is down: in that case the
  /// report's `matchStatus` is set to "failed" and a "failed" outcome is
  /// returned, so the screen can offer "Retry matching".
  Future<MatchOutcome> runMatching(String reportId) async {
    try {
      final response = await _api.match(reportId);
      return MatchOutcome.done(response);
    } catch (error) {
      if (isConnectivityProblem(error) ||
          (error is ApiException && error.statusCode == 404)) {
        await _markFailed(reportId);
        return MatchOutcome.failed(
          'The matching service cannot be reached right now. '
          'Your report is saved and matching will be tried again.',
        );
      }
      if (error is ApiException && error.isConflict) {
        return MatchOutcome.skipped(error.message);
      }
      rethrow;
    }
  }

  /// Runs the matching again for my reports that never finished it
  /// (status "pending" or "failed"). Call it when the app starts and when the
  /// "My reports" screen opens.
  ///
  /// Reports younger than two minutes and reports that are still waiting to
  /// reach the server are left alone. Stops at the first failure, because the
  /// service is probably still down. Returns how many reports were tried.
  Future<int> retryPending(String uid, {int maxReports = 10}) async {
    final snapshot = await _reports
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();
    final cutoff = DateTime.now().subtract(const Duration(minutes: 2));
    final candidates = snapshot.docs
        .map(Report.fromDoc)
        .where(
          (report) =>
              report.isActive &&
              !report.hidden &&
              report.matchStatus != MatchState.done &&
              !report.pendingSync &&
              report.createdAt.isBefore(cutoff),
        )
        .take(maxReports)
        .toList();

    var tried = 0;
    for (final report in candidates) {
      final outcome = await runMatching(report.id);
      tried++;
      if (outcome.isFailed) {
        break;
      }
    }
    return tried;
  }

  /// Best effort: remember that the last run failed. A short wait, because
  /// when the device is offline this write only gets queued.
  Future<void> _markFailed(String reportId) async {
    try {
      await waitForServer(
        _reports
            .doc(reportId)
            .update(Report.matchStatusUpdateMap(MatchState.failed)),
        timeout: const Duration(seconds: 3),
        label: 'match status',
      );
    } catch (error) {
      debugPrint('Could not mark matching as failed for $reportId: $error');
    }
  }

  // ---------------------------------------------------------------------
  // Reading results
  // ---------------------------------------------------------------------

  /// My matches (as the owner of the lost or the found report), best and
  /// newest first as stored. With [activeOnly] resolved matches are left out.
  Stream<List<MatchRecord>> watchMyMatches(
    String uid, {
    bool activeOnly = true,
    int limit = 100,
  }) {
    return _matches
        .where('participants', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final all = snapshot.docs.map(MatchRecord.fromDoc).toList();
      return activeOnly ? all.where((match) => match.isActive).toList() : all;
    });
  }

  /// My matches that involve one particular report, strongest first.
  Stream<List<MatchRecord>> watchMatchesForReport(
    String uid,
    String reportId, {
    bool activeOnly = true,
  }) {
    return watchMyMatches(uid, activeOnly: activeOnly).map((matches) {
      final forReport = matches
          .where(
            (match) =>
                match.lostReportId == reportId ||
                match.foundReportId == reportId,
          )
          .toList();
      forReport.sort((a, b) => b.score.compareTo(a.score));
      return forReport;
    });
  }

  /// How many active matches involve me (dashboard "Potential matches").
  Future<int> countMyActive(String uid) async {
    final snapshot = await _matches
        .where('participants', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .get();
    return snapshot.docs
        .map(MatchRecord.fromDoc)
        .where((match) => match.isActive)
        .length;
  }

  /// Admin only: all matches, optionally of one status.
  Stream<List<MatchRecord>> watchAllMatches({
    MatchRecordStatus? status,
    int limit = 100,
  }) {
    Query<Map<String, dynamic>> query = _matches;
    if (status != null) {
      query = query.where('status', isEqualTo: status.value);
    }
    return query
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(MatchRecord.fromDoc).toList());
  }

  /// Admin only: remove a wrong match record.
  Future<void> deleteMatch(String matchId) {
    return waitForServer(_matches.doc(matchId).delete(), label: 'delete match')
        .then<void>((_) {});
  }
}
