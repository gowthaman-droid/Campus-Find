import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/claim.dart';
import '../models/enums.dart';
import '../models/report.dart';
import '../utils/app_exception.dart';
import '../utils/constants.dart';
import '../utils/validators.dart';
import 'backend_api_service.dart';

/// The claim workflow: found item -> claim -> review -> hand-over.
///
/// Every action that changes a claim AND its report does both in ONE
/// transaction, exactly as firestore.rules demand:
///
///   submit    claims/{reportId}_{uid} is created (report must be active)
///   approve   claim pending -> approved   + report active  -> claimed
///             (other pending claims on the item are rejected too)
///   reject    claim pending -> rejected
///             or approved -> rejected     + report claimed -> active
///   complete  claim approved -> completed + report claimed -> returned
///
/// Transactions only work online. That is intentional: a queued offline
/// approval could be applied hours later without anyone noticing.
///
/// The methods that change something return `true` when the other person was
/// notified through the Python service. A failed notification never undoes the
/// action; the claim lists on both sides always show the true state.
class ClaimService {
  ClaimService({
    FirebaseFirestore? firestore,
    required BackendApiService api,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _api = api;

  final FirebaseFirestore _db;
  final BackendApiService _api;

  CollectionReference<Map<String, dynamic>> get _claims =>
      _db.collection(FirestorePaths.claims);

  CollectionReference<Map<String, dynamic>> get _reports =>
      _db.collection(FirestorePaths.reports);

  // ---------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------

  /// Claims I made, newest first.
  Stream<List<Claim>> watchMyClaims(String uid, {int limit = 100}) {
    return _claims
        .where('claimantId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Claim.fromDoc).toList());
  }

  /// Claims other people made on the items I found, newest first.
  Stream<List<Claim>> watchIncomingClaims(String ownerUid, {int limit = 100}) {
    return _claims
        .where('reportOwnerId', isEqualTo: ownerUid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Claim.fromDoc).toList());
  }

  /// All claims on one found report. [ownerId] is the report owner (the rules
  /// need it in the query).
  Stream<List<Claim>> watchClaimsForReport({
    required String reportId,
    required String ownerId,
  }) {
    return _claims
        .where('reportId', isEqualTo: reportId)
        .where('reportOwnerId', isEqualTo: ownerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Claim.fromDoc).toList());
  }

  /// Admin only: claims waiting for a review.
  Stream<List<Claim>> watchPendingClaims({int limit = 100}) {
    return _claims
        .where('status', isEqualTo: ClaimStatus.pending.value)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Claim.fromDoc).toList());
  }

  /// Admin only: every claim, optionally of one status.
  Stream<List<Claim>> watchAllClaims({ClaimStatus? status, int limit = 100}) {
    Query<Map<String, dynamic>> query = _claims;
    if (status != null) {
      query = query.where('status', isEqualTo: status.value);
    }
    return query
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Claim.fromDoc).toList());
  }

  /// The claim [claimantUid] made on [reportId], or null when there is none.
  ///
  /// Note: Firestore answers "permission-denied" (not "not found") for a claim
  /// that does not exist, because the security rule looks inside the claim.
  /// That case is treated as "no claim".
  Future<Claim?> getMyClaim({
    required String reportId,
    required String claimantUid,
  }) async {
    try {
      final doc = await _claims.doc(Claim.idFor(reportId, claimantUid)).get();
      return doc.exists ? Claim.fromDoc(doc) : null;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return null;
      }
      rethrow;
    }
  }

  /// One claim, live. Emits null when it does not exist (see [getMyClaim]).
  Stream<Claim?> watchClaim(String claimId) async* {
    try {
      await for (final doc in _claims.doc(claimId).snapshots()) {
        yield doc.exists ? Claim.fromDoc(doc) : null;
      }
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        yield null;
        return;
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  /// Claim a found item.
  Future<bool> submitClaim({
    required Report report,
    required AppUser claimant,
    required String message,
    required String verificationDetails,
  }) async {
    if (!report.isFound) {
      throw const AppException('Only found items can be claimed.');
    }
    if (report.userId == claimant.uid) {
      throw const AppException(
        'You cannot claim an item that you reported yourself.',
      );
    }
    final problem = Validators.claimMessage(message) ??
        Validators.verificationDetails(verificationDetails);
    if (problem != null) {
      throw AppException(problem);
    }
    if (claimant.name.trim().isEmpty) {
      throw const AppException(
        'Please add your name to your profile before making a claim.',
      );
    }
    final existing = await getMyClaim(
      reportId: report.id,
      claimantUid: claimant.uid,
    );
    if (existing != null) {
      throw AppException(
        'You already made a claim on this item (${existing.status.label}).',
      );
    }

    final claimRef = _claims.doc(Claim.idFor(report.id, claimant.uid));
    final reportRef = _reports.doc(report.id);
    String? blocked;
    try {
      blocked = await _db.runTransaction<String?>(
        (tx) async {
          final reportSnap = await tx.get(reportRef);
          if (!reportSnap.exists) {
            return 'This report no longer exists.';
          }
          final current = Report.fromDoc(reportSnap);
          if (!current.isFound || current.hidden) {
            return 'This item is not available to claim.';
          }
          if (!current.isActive) {
            return 'This item has already been claimed or returned.';
          }
          if (current.userId == claimant.uid) {
            return 'You cannot claim an item that you reported yourself.';
          }
          tx.set(
            claimRef,
            Claim.createMap(
              reportId: current.id,
              reportOwnerId: current.userId,
              claimantId: claimant.uid,
              claimantName: claimant.name,
              claimantPhone: claimant.phone,
              reportItemName: current.itemName,
              message: message,
              verificationDetails: verificationDetails,
            ),
          );
          return null;
        },
        timeout: AppConstants.transactionTimeout,
        maxAttempts: 3,
      );
    } on FirebaseException catch (error) {
      throw explainWriteFailure(error);
    }
    if (blocked != null) {
      throw AppException(blocked);
    }
    return _notify(ApiEvents.claimSubmitted, claimId: claimRef.id);
  }

  /// The finder (or an admin) approves a claim. The item becomes "claimed" and
  /// every other pending claim on it is rejected.
  Future<bool> approveClaim({
    required Claim claim,
    required String reviewerUid,
    String note = '',
  }) async {
    final others = await _otherPendingClaims(claim);
    final claimRef = _claims.doc(claim.claimId);
    final reportRef = _reports.doc(claim.reportId);
    final autoRejected = <String>[];

    String? blocked;
    try {
      blocked = await _db.runTransaction<String?>(
        (tx) async {
          // All reads first, then all writes.
          final claimSnap = await tx.get(claimRef);
          final reportSnap = await tx.get(reportRef);
          final otherSnaps = <DocumentSnapshot<Map<String, dynamic>>>[];
          for (final other in others) {
            otherSnaps.add(await tx.get(_claims.doc(other.claimId)));
          }

          if (!claimSnap.exists || !reportSnap.exists) {
            return 'This claim or item no longer exists.';
          }
          if (!Claim.fromDoc(claimSnap).isPending) {
            return 'This claim was already reviewed.';
          }
          if (!Report.fromDoc(reportSnap).isActive) {
            return 'This item is no longer available: it was already claimed or returned.';
          }

          tx.update(
            claimRef,
            Claim.reviewMap(
              status: ClaimStatus.approved,
              reviewerUid: reviewerUid,
              note: note,
            ),
          );
          tx.update(reportRef, Report.statusUpdateMap(ReportStatus.claimed));

          // The transaction can run more than once; start from a clean list.
          autoRejected.clear();
          for (final snap in otherSnaps) {
            if (snap.exists && Claim.fromDoc(snap).isPending) {
              tx.update(
                snap.reference,
                Claim.reviewMap(
                  status: ClaimStatus.rejected,
                  reviewerUid: reviewerUid,
                  note: 'Another claim was approved for this item.',
                ),
              );
              autoRejected.add(snap.id);
            }
          }
          return null;
        },
        timeout: AppConstants.transactionTimeout,
        maxAttempts: 3,
      );
    } on FirebaseException catch (error) {
      throw explainWriteFailure(error);
    }
    if (blocked != null) {
      throw AppException(blocked);
    }

    final notified = await _notify(ApiEvents.claimApproved, claimId: claim.claimId);
    for (final id in autoRejected) {
      unawaited(_notify(ApiEvents.claimRejected, claimId: id));
    }
    return notified;
  }

  /// Reject a pending claim, or take back an approval (the item becomes
  /// "active" again).
  Future<bool> rejectClaim({
    required Claim claim,
    required String reviewerUid,
    String note = '',
  }) async {
    final claimRef = _claims.doc(claim.claimId);
    final reportRef = _reports.doc(claim.reportId);

    String? blocked;
    try {
      blocked = await _db.runTransaction<String?>(
        (tx) async {
          final claimSnap = await tx.get(claimRef);
          if (!claimSnap.exists) {
            return 'This claim no longer exists.';
          }
          final current = Claim.fromDoc(claimSnap);

          if (current.isPending) {
            tx.update(
              claimRef,
              Claim.reviewMap(
                status: ClaimStatus.rejected,
                reviewerUid: reviewerUid,
                note: note,
              ),
            );
            return null;
          }

          if (current.isApproved) {
            final reportSnap = await tx.get(reportRef);
            if (!reportSnap.exists) {
              return 'This item no longer exists.';
            }
            if (!Report.fromDoc(reportSnap).isClaimed) {
              return 'The item is no longer in the "claimed" state.';
            }
            tx.update(
              claimRef,
              Claim.reviewMap(
                status: ClaimStatus.rejected,
                reviewerUid: reviewerUid,
                note: note,
              ),
            );
            tx.update(reportRef, Report.statusUpdateMap(ReportStatus.active));
            return null;
          }

          return 'This claim was already finished.';
        },
        timeout: AppConstants.transactionTimeout,
        maxAttempts: 3,
      );
    } on FirebaseException catch (error) {
      throw explainWriteFailure(error);
    }
    if (blocked != null) {
      throw AppException(blocked);
    }
    return _notify(ApiEvents.claimRejected, claimId: claim.claimId);
  }

  /// The hand-over happened: the claim is completed and the item is returned.
  Future<bool> completeClaim({
    required Claim claim,
    required String reviewerUid,
    String note = '',
  }) async {
    final claimRef = _claims.doc(claim.claimId);
    final reportRef = _reports.doc(claim.reportId);

    String? blocked;
    try {
      blocked = await _db.runTransaction<String?>(
        (tx) async {
          final claimSnap = await tx.get(claimRef);
          final reportSnap = await tx.get(reportRef);
          if (!claimSnap.exists || !reportSnap.exists) {
            return 'This claim or item no longer exists.';
          }
          if (!Claim.fromDoc(claimSnap).isApproved) {
            return 'Only an approved claim can be completed.';
          }
          final report = Report.fromDoc(reportSnap);
          if (report.isReturned) {
            return 'This item was already marked as returned.';
          }
          if (!report.isClaimed) {
            return 'The item is no longer in the "claimed" state.';
          }
          tx.update(
            claimRef,
            Claim.reviewMap(
              status: ClaimStatus.completed,
              reviewerUid: reviewerUid,
              note: note,
            ),
          );
          tx.update(
            reportRef,
            Report.returnedUpdateMap(
              resolvedBy: reviewerUid,
              returnedTo: claim.claimantName,
            ),
          );
          return null;
        },
        timeout: AppConstants.transactionTimeout,
        maxAttempts: 3,
      );
    } on FirebaseException catch (error) {
      throw explainWriteFailure(error);
    }
    if (blocked != null) {
      throw AppException(blocked);
    }
    return _notify(ApiEvents.claimCompleted, claimId: claim.claimId);
  }

  /// The claimant takes back a claim that is still pending.
  Future<void> withdrawClaim({
    required Claim claim,
    required String claimantUid,
  }) async {
    if (claim.claimantId != claimantUid) {
      throw const AppException('You can only withdraw your own claim.');
    }
    final claimRef = _claims.doc(claim.claimId);

    String? blocked;
    try {
      blocked = await _db.runTransaction<String?>(
        (tx) async {
          final snap = await tx.get(claimRef);
          if (!snap.exists) {
            return 'This claim no longer exists.';
          }
          if (!Claim.fromDoc(snap).isPending) {
            return 'Only a pending claim can be withdrawn.';
          }
          tx.delete(claimRef);
          return null;
        },
        timeout: AppConstants.transactionTimeout,
        maxAttempts: 3,
      );
    } on FirebaseException catch (error) {
      throw explainWriteFailure(error);
    }
    if (blocked != null) {
      throw AppException(blocked);
    }
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  /// Pending claims on the same item, apart from [claim] itself.
  Future<List<Claim>> _otherPendingClaims(Claim claim) async {
    final snapshot = await _claims
        .where('reportId', isEqualTo: claim.reportId)
        .where('reportOwnerId', isEqualTo: claim.reportOwnerId)
        .where('status', isEqualTo: ClaimStatus.pending.value)
        .get();
    return snapshot.docs
        .map(Claim.fromDoc)
        .where((other) => other.claimId != claim.claimId)
        .toList();
  }

  /// Tells the Python service to notify the other person. Never throws.
  Future<bool> _notify(String eventType, {required String claimId}) async {
    try {
      await _api.sendEvent(eventType, claimId: claimId);
      return true;
    } catch (error) {
      debugPrint('Event $eventType failed: $error');
      return false;
    }
  }
}
