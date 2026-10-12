import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/contact_info.dart';
import '../models/enums.dart';
import '../models/report.dart';
import '../models/report_draft.dart';
import '../services/match_service.dart';
import '../services/report_service.dart';
import '../utils/app_exception.dart';
import 'provider_utils.dart';

/// What happened when a report was submitted.
class SubmitResult {
  const SubmitResult({
    required this.reportId,
    required this.synced,
    this.matching,
  });

  final String reportId;

  /// False when the device was offline: the report is saved on the device and
  /// will be sent as soon as the connection is back.
  final bool synced;

  /// The answer of the matching service. Null when matching was not tried yet
  /// (offline) or failed with an unexpected error.
  final MatchOutcome? matching;

  int get matchCount => matching?.response?.matches.length ?? 0;
  bool get hasStrongMatch => matching?.hasStrongMatch ?? false;
  bool get matchingFailed => matching?.isFailed ?? false;

  /// A friendly sentence for the person.
  String get message {
    if (!synced) {
      return 'You seem to be offline. Your report is saved on this phone and '
          'will be sent automatically when you are back online.';
    }
    final outcome = matching;
    if (outcome == null || outcome.kind == MatchOutcomeKind.skipped) {
      return 'Your report was saved.';
    }
    if (outcome.isFailed) {
      return 'Your report was saved. Matching could not run right now and '
          'will be tried again automatically.';
    }
    if (matchCount == 0) {
      return 'Your report was saved. We will notify you if a match appears.';
    }
    if (matchCount == 1) {
      return 'Your report was saved. We found 1 possible match!';
    }
    return 'Your report was saved. We found $matchCount possible matches!';
  }
}

/// A person's own reports and everything they do with them.
///
///  * `myReports` is a LIVE list: it updates by itself when a report changes
///    on the server (a match was found, a claim was approved, ...).
///  * Submitting a report saves it first, then asks the matching service. If
///    the service is down the report is still safe and matching is retried.
class ReportProvider extends ChangeNotifier with SafeNotifier {
  ReportProvider({
    required ReportService reports,
    required MatchService matches,
  })  : _reports = reports,
        _matches = matches;

  final ReportService _reports;
  final MatchService _matches;

  StreamSubscription<List<Report>>? _subscription;
  AppUser? _profile;
  String? _uid;

  List<Report> _myReports = const <Report>[];
  bool _loading = false;
  String? _error;
  bool _saving = false;
  double? _uploadProgress;

  // ---------------------------------------------------------------------
  // What the screens can read
  // ---------------------------------------------------------------------

  List<Report> get myReports => _myReports;

  List<Report> get lostReports =>
      _myReports.where((report) => report.isLost).toList();

  List<Report> get foundReports =>
      _myReports.where((report) => report.isFound).toList();

  /// True until the first answer arrives.
  bool get loading => _loading;

  /// Why the list could not be loaded (friendly sentence), or null.
  String? get error => _error;

  /// True while a report is being submitted, edited, deleted or returned.
  bool get saving => _saving;

  /// 0.0 to 1.0 while a photo is uploading, otherwise null.
  double? get uploadProgress => _uploadProgress;

  /// Active reports whose matching has not finished yet.
  int get pendingMatchCount => _myReports
      .where(
        (report) =>
            report.isActive &&
            !report.pendingSync &&
            report.matchStatus != MatchState.done,
      )
      .length;

  Report? byId(String id) {
    for (final report in _myReports) {
      if (report.id == id) {
        return report;
      }
    }
    return null;
  }

  /// One report, live (for the details screen). Emits null when it does not
  /// exist or may not be seen. Use it with a StreamBuilder.
  Stream<Report?> watchReport(String id) => _reports.watchReport(id);

  /// The reporter's phone and e-mail. Null unless the viewer is the reporter,
  /// an admin, or has an approved claim on this report: this is how contact
  /// details are only shown to authorised people.
  Future<ContactInfo?> loadContact(String reportId) {
    return _reports.getContact(reportId);
  }

  // ---------------------------------------------------------------------
  // Following the signed-in person
  // ---------------------------------------------------------------------

  /// Called by the ProxyProvider whenever the sign-in state changes.
  /// Safe to call many times: nothing restarts while the person stays the same.
  void bindUser(AppUser? profile) {
    _profile = profile;
    final newUid = profile?.uid;
    if (newUid == _uid) {
      return;
    }
    _uid = newUid;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _myReports = const <Report>[];
    _error = null;
    _loading = false;

    if (newUid != null) {
      _loading = true;
      _subscription = _reports.watchMyReports(newUid).listen(
            _onReports,
            onError: _onError,
          );
      unawaited(_retryPendingMatches(newUid));
    }
    notifyListenersSoon();
  }

  void _onReports(List<Report> reports) {
    _myReports = reports;
    _loading = false;
    _error = null;
    notifyListeners();
  }

  void _onError(Object error) {
    _error = friendlyError(error);
    _loading = false;
    notifyListeners();
  }

  Future<void> _retryPendingMatches(String uid) async {
    try {
      await _matches.retryPending(uid);
    } catch (error) {
      debugPrint('Retrying pending matching failed: $error');
    }
  }

  /// Runs matching again for reports that never finished it. Use it for
  /// pull-to-refresh on "My reports".
  Future<void> retryPendingMatches() async {
    final uid = _uid;
    if (uid != null) {
      await _retryPendingMatches(uid);
    }
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  /// Saves a new report (with its photo) and asks the matching service.
  Future<ActionResult<SubmitResult>> submitReport(ReportDraft draft) {
    return _saveGuard<SubmitResult>(() async {
      final reporter = _profile;
      if (reporter == null) {
        return ActionResult<SubmitResult>.failed('Please log in first.');
      }
      final created = await _reports.createReport(
        reporter: reporter,
        draft: draft,
        onUploadProgress: _onUploadProgress,
      );

      MatchOutcome? outcome;
      if (created.synced) {
        outcome = await _tryMatching(created.reportId);
      }
      final result = SubmitResult(
        reportId: created.reportId,
        synced: created.synced,
        matching: outcome,
      );
      return ActionResult<SubmitResult>.ok(
        message: result.message,
        warning: !created.synced || result.matchingFailed,
        data: result,
      );
    });
  }

  /// Saves the changes of a report and matches it again.
  /// `data` is true when the change reached the server.
  Future<ActionResult<bool>> updateReport(Report existing, ReportDraft draft) {
    return _saveGuard<bool>(() async {
      final synced = await _reports.updateReport(
        existing: existing,
        draft: draft,
        onUploadProgress: _onUploadProgress,
      );
      if (!synced) {
        return ActionResult<bool>.ok(
          message: 'Saved on this phone. It will be sent when you are online again.',
          warning: true,
          data: false,
        );
      }
      final outcome = await _tryMatching(existing.id);
      return ActionResult<bool>.ok(
        message: outcome != null && outcome.isFailed
            ? 'Report updated. Matching will be tried again automatically.'
            : 'Report updated.',
        warning: outcome != null && outcome.isFailed,
        data: true,
      );
    });
  }

  /// The "Retry matching" button.
  Future<ActionResult<MatchOutcome>> retryMatching(String reportId) {
    return _saveGuard<MatchOutcome>(() async {
      final outcome = await _matches.runMatching(reportId);
      if (outcome.isFailed) {
        return ActionResult<MatchOutcome>.ok(
          message: outcome.message,
          warning: true,
          data: outcome,
        );
      }
      final count = outcome.response?.matches.length ?? 0;
      final plural = count == 1 ? '' : 'es';
      return ActionResult<MatchOutcome>.ok(
        message: count == 0
            ? 'No match yet. We will notify you if one appears.'
            : 'We found $count possible match$plural!',
        data: outcome,
      );
    });
  }

  /// Deletes a report that is still active.
  Future<ActionResult<void>> deleteReport(Report report) {
    return _saveGuard<void>(() async {
      final uid = _uid;
      if (uid == null) {
        return ActionResult<void>.failed('Please log in first.');
      }
      final synced = await _reports.deleteReport(report, actorUid: uid);
      return ActionResult<void>.ok(
        message: synced
            ? 'Report deleted.'
            : 'Deleted on this phone. It will be sent when you are online again.',
        warning: !synced,
      );
    });
  }

  /// Marks the item as handed back (no claim involved). For an item with an
  /// approved claim use ClaimProvider.complete instead.
  Future<ActionResult<void>> markReturned(Report report, String returnedTo) {
    return _saveGuard<void>(() async {
      final uid = _uid;
      if (uid == null) {
        return ActionResult<void>.failed('Please log in first.');
      }
      final notified = await _reports.markReturned(
        report: report,
        userId: uid,
        returnedTo: returnedTo,
      );
      return ActionResult<void>.ok(
        message: 'Marked as returned. Thank you!',
        warning: !notified,
      );
    });
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  /// Matching must never make a saved report look like a failure.
  Future<MatchOutcome?> _tryMatching(String reportId) async {
    try {
      return await _matches.runMatching(reportId);
    } catch (error) {
      debugPrint('Matching for $reportId failed: $error');
      return null;
    }
  }

  void _onUploadProgress(double progress) {
    _uploadProgress = progress;
    notifyListeners();
  }

  Future<ActionResult<T>> _saveGuard<T>(
    Future<ActionResult<T>> Function() action,
  ) async {
    if (_saving) {
      return ActionResult<T>.failed('Please wait a moment and try again.');
    }
    _saving = true;
    _uploadProgress = null;
    notifyListeners();
    try {
      return await action();
    } catch (error) {
      return ActionResult<T>.failed(friendlyError(error));
    } finally {
      _saving = false;
      _uploadProgress = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
