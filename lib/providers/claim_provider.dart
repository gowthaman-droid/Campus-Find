import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/claim.dart';
import '../models/report.dart';
import '../services/claim_service.dart';
import '../utils/app_exception.dart';
import 'provider_utils.dart';

/// Claims, from both sides:
///  * `myClaims`       - claims I made on other people's found items
///  * `incomingClaims` - claims other people made on the items I found
///
/// Both lists are live. The actions (submit, approve, reject, complete,
/// withdraw) work for the finder AND for admins: the security rules allow an
/// admin to review any claim.
class ClaimProvider extends ChangeNotifier with SafeNotifier {
  ClaimProvider({required ClaimService claims}) : _claims = claims;

  final ClaimService _claims;

  AppUser? _profile;
  String? _uid;
  StreamSubscription<List<Claim>>? _mineSubscription;
  StreamSubscription<List<Claim>>? _incomingSubscription;

  List<Claim> _myClaims = const <Claim>[];
  List<Claim> _incomingClaims = const <Claim>[];
  bool _loading = false;
  String? _error;
  bool _busy = false;

  // ---------------------------------------------------------------------
  // What the screens can read
  // ---------------------------------------------------------------------

  List<Claim> get myClaims => _myClaims;
  List<Claim> get incomingClaims => _incomingClaims;

  bool get loading => _loading;
  String? get error => _error;

  /// True while an action is running (disable the buttons).
  bool get busy => _busy;

  /// Claims waiting for MY review (shown as a badge).
  int get pendingIncomingCount =>
      _incomingClaims.where((claim) => claim.isPending).length;

  /// My claim on a report, or null.
  Claim? myClaimFor(String reportId) {
    for (final claim in _myClaims) {
      if (claim.reportId == reportId) {
        return claim;
      }
    }
    return null;
  }

  /// All claims on one of MY found reports (from the live list).
  List<Claim> incomingFor(String reportId) =>
      _incomingClaims.where((claim) => claim.reportId == reportId).toList();

  /// A live list of all claims on one found report. [report] must be the
  /// report's owner's, or the viewer must be an admin.
  Stream<List<Claim>> claimsForReport(Report report) {
    return _claims.watchClaimsForReport(
      reportId: report.id,
      ownerId: report.userId,
    );
  }

  // ---------------------------------------------------------------------
  // Following the signed-in person
  // ---------------------------------------------------------------------

  void bindUser(AppUser? profile) {
    _profile = profile;
    final newUid = profile?.uid;
    if (newUid == _uid) {
      return;
    }
    _uid = newUid;
    unawaited(_mineSubscription?.cancel());
    unawaited(_incomingSubscription?.cancel());
    _mineSubscription = null;
    _incomingSubscription = null;
    _myClaims = const <Claim>[];
    _incomingClaims = const <Claim>[];
    _error = null;
    _loading = false;

    if (newUid != null) {
      _loading = true;
      _mineSubscription = _claims.watchMyClaims(newUid).listen(
        (claims) {
          _myClaims = claims;
          _loading = false;
          notifyListeners();
        },
        onError: _onError,
      );
      _incomingSubscription = _claims.watchIncomingClaims(newUid).listen(
        (claims) {
          _incomingClaims = claims;
          _loading = false;
          notifyListeners();
        },
        onError: _onError,
      );
    }
    notifyListenersSoon();
  }

  void _onError(Object error) {
    _error = friendlyError(error);
    _loading = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  /// Claim a found item.
  Future<ActionResult<void>> submitClaim({
    required Report report,
    required String message,
    required String verificationDetails,
  }) {
    return _run(() async {
      final claimant = _profile;
      if (claimant == null) {
        return ActionResult<void>.failed('Please log in first.');
      }
      final notified = await _claims.submitClaim(
        report: report,
        claimant: claimant,
        message: message,
        verificationDetails: verificationDetails,
      );
      return _result(
        notified,
        'Your claim was sent. The finder will review it.',
        'Your claim was sent, but the finder could not be notified right now. '
            'They will still see it in their claims list.',
      );
    });
  }

  /// The finder (or an admin) approves a claim.
  Future<ActionResult<void>> approve(Claim claim, {String note = ''}) {
    return _run(() async {
      final reviewer = _uid;
      if (reviewer == null) {
        return ActionResult<void>.failed('Please log in first.');
      }
      final notified = await _claims.approveClaim(
        claim: claim,
        reviewerUid: reviewer,
        note: note,
      );
      return _result(
        notified,
        'Claim approved. The claimant can now see your contact details.',
        'Claim approved, but the claimant could not be notified right now.',
      );
    });
  }

  /// Reject a pending claim, or take back an approval.
  Future<ActionResult<void>> reject(Claim claim, {String note = ''}) {
    return _run(() async {
      final reviewer = _uid;
      if (reviewer == null) {
        return ActionResult<void>.failed('Please log in first.');
      }
      final notified = await _claims.rejectClaim(
        claim: claim,
        reviewerUid: reviewer,
        note: note,
      );
      return _result(
        notified,
        'Claim rejected.',
        'Claim rejected, but the claimant could not be notified right now.',
      );
    });
  }

  /// The hand-over happened: the item counts as returned.
  Future<ActionResult<void>> complete(Claim claim, {String note = ''}) {
    return _run(() async {
      final reviewer = _uid;
      if (reviewer == null) {
        return ActionResult<void>.failed('Please log in first.');
      }
      final notified = await _claims.completeClaim(
        claim: claim,
        reviewerUid: reviewer,
        note: note,
      );
      return _result(
        notified,
        'Item marked as returned. Thank you!',
        'Item marked as returned, but the claimant could not be notified right now.',
      );
    });
  }

  /// Take back my own pending claim.
  Future<ActionResult<void>> withdraw(Claim claim) {
    return _run(() async {
      final uid = _uid;
      if (uid == null) {
        return ActionResult<void>.failed('Please log in first.');
      }
      await _claims.withdrawClaim(claim: claim, claimantUid: uid);
      return ActionResult<void>.ok(message: 'Claim withdrawn.');
    });
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  ActionResult<void> _result(bool notified, String okText, String warnText) {
    return ActionResult<void>.ok(
      message: notified ? okText : warnText,
      warning: !notified,
    );
  }

  Future<ActionResult<void>> _run(
    Future<ActionResult<void>> Function() action,
  ) async {
    if (_busy) {
      return ActionResult<void>.failed('Please wait a moment and try again.');
    }
    _busy = true;
    notifyListeners();
    try {
      return await action();
    } catch (error) {
      return ActionResult<void>.failed(friendlyError(error));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_mineSubscription?.cancel());
    unawaited(_incomingSubscription?.cancel());
    super.dispose();
  }
}
