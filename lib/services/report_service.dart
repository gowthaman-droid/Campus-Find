import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/claim.dart';
import '../models/contact_info.dart';
import '../models/enums.dart';
import '../models/report.dart';
import '../models/report_draft.dart';
import '../models/search_filters.dart';
import '../utils/app_exception.dart';
import '../utils/constants.dart';
import '../utils/firestore_count.dart';
import '../utils/firestore_write.dart';
import 'backend_api_service.dart';
import 'storage_service.dart';

/// One page of search results.
class ReportPage {
  const ReportPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
  });

  final List<Report> items;

  /// Pass this to the next `fetchPage` call to get the following page.
  final DocumentSnapshot<Map<String, dynamic>>? cursor;

  final bool hasMore;
}

class CreateReportResult {
  const CreateReportResult({required this.reportId, required this.synced});

  final String reportId;

  /// False when the device was offline: Firestore keeps the report on the
  /// device and sends it as soon as the connection is back. The matching
  /// service can only be asked once the report has reached the server.
  final bool synced;
}

/// Everything about lost/found reports in Firestore (`reports/{id}`).
///
/// Writes are built with the maps in the Report model, which are checked
/// against firestore.rules. Matching is NOT started here: after
/// [createReport] or [updateReport] the caller runs MatchService.runMatching.
class ReportService {
  ReportService({
    FirebaseFirestore? firestore,
    required StorageService storage,
    required BackendApiService api,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage,
        _api = api;

  final FirebaseFirestore _db;
  final StorageService _storage;
  final BackendApiService _api;

  CollectionReference<Map<String, dynamic>> get _reports =>
      _db.collection(FirestorePaths.reports);

  CollectionReference<Map<String, dynamic>> get _claims =>
      _db.collection(FirestorePaths.claims);

  // ---------------------------------------------------------------------
  // Creating, editing, deleting
  // ---------------------------------------------------------------------

  /// Uploads the photo (if any) and saves the report together with the
  /// reporter's private contact details in ONE batch.
  Future<CreateReportResult> createReport({
    required AppUser reporter,
    required ReportDraft draft,
    void Function(double progress)? onUploadProgress,
  }) async {
    final problem = draft.validate();
    if (problem != null) {
      throw AppException(problem);
    }
    if (reporter.phone.trim().length < AppConstants.phoneMin) {
      throw const AppException(
        'Please add your phone number to your profile before reporting an item.',
      );
    }

    final reportRef = _reports.doc();
    UploadedImage? image;
    final newImage = draft.newImage;
    if (newImage != null) {
      image = await _storage.uploadReportImage(
        uid: reporter.uid,
        reportId: reportRef.id,
        image: newImage,
        onProgress: onUploadProgress,
      );
    }

    final batch = _db.batch();
    batch.set(
      reportRef,
      Report.createMap(
        id: reportRef.id,
        type: draft.type,
        userId: reporter.uid,
        reporterName: reporter.name,
        itemName: draft.itemName,
        category: draft.category,
        description: draft.description,
        additionalDetails: draft.additionalDetails,
        location: draft.location,
        locationDetail: draft.locationDetail,
        eventAt: draft.eventAt,
        imageUrl: image?.url ?? '',
        imagePath: image?.path ?? '',
      ),
    );
    batch.set(
      reportRef
          .collection(FirestorePaths.reportPrivate)
          .doc(FirestorePaths.contactDoc),
      ContactInfo.writeMap(
        userId: reporter.uid,
        phone: reporter.phone,
        email: reporter.email,
      ),
    );

    try {
      final synced = await waitForServer(batch.commit(), label: 'new report');
      return CreateReportResult(reportId: reportRef.id, synced: synced);
    } catch (_) {
      if (image != null) {
        await _storage.deleteQuietly(image.path);
      }
      rethrow;
    }
  }

  /// The owner edits a report. Matching is reset to "pending" (the content
  /// changed), so call MatchService.runMatching afterwards.
  /// Returns false when the change is only queued on the device (offline).
  Future<bool> updateReport({
    required Report existing,
    required ReportDraft draft,
    void Function(double progress)? onUploadProgress,
  }) async {
    if (existing.isReturned) {
      throw const AppException('A returned report can no longer be edited.');
    }
    final problem = draft.validate();
    if (problem != null) {
      throw AppException(problem);
    }

    var imageUrl = existing.imageUrl;
    var imagePath = existing.imagePath;
    UploadedImage? uploaded;
    final newImage = draft.newImage;
    if (newImage != null) {
      uploaded = await _storage.uploadReportImage(
        uid: existing.userId,
        reportId: existing.id,
        image: newImage,
        onProgress: onUploadProgress,
      );
      imageUrl = uploaded.url;
      imagePath = uploaded.path;
    } else if (draft.removeImage) {
      imageUrl = '';
      imagePath = '';
    }

    final bool synced;
    try {
      synced = await waitForServer(
        _reports.doc(existing.id).update(
              Report.contentUpdateMap(
                itemName: draft.itemName,
                category: draft.category,
                description: draft.description,
                additionalDetails: draft.additionalDetails,
                location: draft.location,
                locationDetail: draft.locationDetail,
                eventAt: draft.eventAt,
                imageUrl: imageUrl,
                imagePath: imagePath,
              ),
            ),
        label: 'report update',
      );
    } catch (_) {
      if (uploaded != null) {
        await _storage.deleteQuietly(uploaded.path);
      }
      rethrow;
    }

    if (synced &&
        existing.imagePath.isNotEmpty &&
        existing.imagePath != imagePath) {
      await _storage.deleteQuietly(existing.imagePath);
    }
    return synced;
  }

  /// Deletes a report that is still active (admins may delete any report),
  /// together with its contact document and photo. Pending claims on it are
  /// rejected in the same batch so nobody is left waiting.
  Future<bool> deleteReport(
    Report report, {
    required String actorUid,
    bool asAdmin = false,
  }) async {
    if (!asAdmin && !report.isActive) {
      throw const AppException(
        'Only reports that are still active can be deleted.',
      );
    }
    final pending = report.isFound
        ? (await _claimsOnReport(report)).where((claim) => claim.isPending)
        : <Claim>[];

    final reportRef = _reports.doc(report.id);
    final batch = _db.batch();
    for (final claim in pending) {
      batch.update(
        _claims.doc(claim.claimId),
        Claim.reviewMap(
          status: ClaimStatus.rejected,
          reviewerUid: actorUid,
          note: 'The report was deleted.',
        ),
      );
    }
    batch.delete(
      reportRef
          .collection(FirestorePaths.reportPrivate)
          .doc(FirestorePaths.contactDoc),
    );
    batch.delete(reportRef);

    final synced = await waitForServer(batch.commit(), label: 'report delete');
    if (synced) {
      await _storage.deleteQuietly(report.imagePath);
    }
    return synced;
  }

  /// Marks an item as handed back without a claim (for example the owner of a
  /// lost item got it back, or the finder returned it in person).
  /// Pending claims on the report are rejected in the same transaction.
  /// A report with an APPROVED claim must be finished with
  /// ClaimService.completeClaim instead.
  ///
  /// Returns true when the other people were notified.
  Future<bool> markReturned({
    required Report report,
    required String userId,
    required String returnedTo,
  }) async {
    final name = returnedTo.trim();
    if (name.isEmpty) {
      throw const AppException(
        'Please enter the name of the person who received the item.',
      );
    }
    if (name.length > AppConstants.returnedToMax) {
      throw AppException(
        'The name must be at most ${AppConstants.returnedToMax} characters.',
      );
    }
    if (report.isReturned) {
      throw const AppException('This item was already marked as returned.');
    }

    final openClaims = report.isFound
        ? await _claimsOnReport(report)
        : const <Claim>[];
    if (openClaims.any((claim) => claim.isApproved)) {
      throw const AppException(
        'This item has an approved claim. Use "Complete hand-over" on that '
        'claim instead.',
      );
    }
    final pending = openClaims.where((claim) => claim.isPending).toList();
    final reportRef = _reports.doc(report.id);

    String? problem;
    try {
      problem = await _db.runTransaction<String?>(
        (tx) async {
          final reportSnap = await tx.get(reportRef);
          final claimSnaps = <DocumentSnapshot<Map<String, dynamic>>>[];
          for (final claim in pending) {
            claimSnaps.add(await tx.get(_claims.doc(claim.claimId)));
          }
          if (!reportSnap.exists) {
            return 'This report no longer exists.';
          }
          if (Report.fromDoc(reportSnap).isReturned) {
            return 'This item was already marked as returned.';
          }
          for (final snap in claimSnaps) {
            if (snap.exists && Claim.fromDoc(snap).isApproved) {
              return 'A claim on this item was approved in the meantime. '
                  'Complete that claim instead.';
            }
          }
          tx.update(
            reportRef,
            Report.returnedUpdateMap(resolvedBy: userId, returnedTo: name),
          );
          for (final snap in claimSnaps) {
            if (snap.exists && Claim.fromDoc(snap).isPending) {
              tx.update(
                snap.reference,
                Claim.reviewMap(
                  status: ClaimStatus.rejected,
                  reviewerUid: userId,
                  note: 'The item was returned.',
                ),
              );
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
    if (problem != null) {
      throw AppException(problem);
    }

    try {
      await _api.sendEvent(ApiEvents.itemReturned, reportId: report.id);
      return true;
    } catch (error) {
      debugPrint('Event ${ApiEvents.itemReturned} failed: $error');
      return false;
    }
  }

  /// Admin only: hide (or show again) a report that should not be public.
  Future<bool> setHidden({
    required String reportId,
    required bool hidden,
    required String adminUid,
    String reason = '',
  }) async {
    if (reason.trim().length > AppConstants.hiddenReasonMax) {
      throw AppException(
        'The reason must be at most ${AppConstants.hiddenReasonMax} characters.',
      );
    }
    return waitForServer(
      _reports.doc(reportId).update(
            Report.hideUpdateMap(
              hidden: hidden,
              adminUid: adminUid,
              reason: reason,
            ),
          ),
      label: 'hide report',
    );
  }

  // ---------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------

  /// The query behind the Search screen. Every filter is applied by
  /// Firestore itself, not just on the screen.
  ///
  ///  * `hidden == false` is always included: the security rules require it.
  ///  * Typed text becomes `keywords array-contains-any [words]`.
  ///  * Needs the indexes of firestore.indexes.json.
  Query<Map<String, dynamic>> browseQuery(SearchFilters filters) {
    Query<Map<String, dynamic>> query = _reports.where('hidden', isEqualTo: false);
    final type = filters.type;
    if (type != null) {
      query = query.where('type', isEqualTo: type.value);
    }
    final status = filters.status;
    if (status != null) {
      query = query.where('status', isEqualTo: status.value);
    }
    final category = filters.category;
    if (category != null) {
      query = query.where('category', isEqualTo: category);
    }
    final location = filters.location;
    if (location != null) {
      query = query.where('location', isEqualTo: location);
    }
    final tokens = filters.tokens;
    if (tokens.isNotEmpty) {
      query = query.where('keywords', arrayContainsAny: tokens);
    }
    return query.orderBy('createdAt', descending: true);
  }

  /// Loads one page, newest first. Pass the previous page's `cursor` to get
  /// the next page.
  Future<ReportPage> fetchPage(
    SearchFilters filters, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int pageSize = AppConstants.pageSize,
  }) async {
    var query = browseQuery(filters).limit(pageSize);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    final snapshot = await query.get();
    final items = snapshot.docs.map(Report.fromDoc).toList();
    return ReportPage(
      items: items,
      cursor: snapshot.docs.isEmpty ? startAfter : snapshot.docs.last,
      hasMore: snapshot.docs.length >= pageSize,
    );
  }

  /// A person's own reports, live. Changes of the "waiting to sync" state are
  /// included so the list updates when an offline report reaches the server.
  Stream<List<Report>> watchMyReports(
    String uid, {
    ReportType? type,
    int limit = 100,
  }) {
    Query<Map<String, dynamic>> query = _reports.where('userId', isEqualTo: uid);
    if (type != null) {
      query = query.where('type', isEqualTo: type.value);
    }
    return query
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) => snapshot.docs.map(Report.fromDoc).toList());
  }

  /// One report, live. Emits null when it does not exist or you may not see it
  /// (for example it was hidden by an admin).
  Stream<Report?> watchReport(String id) async* {
    try {
      await for (final doc
          in _reports.doc(id).snapshots(includeMetadataChanges: true)) {
        yield doc.exists ? Report.fromDoc(doc) : null;
      }
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        yield null;
        return;
      }
      rethrow;
    }
  }

  /// One report, once. Null when it does not exist or you may not see it.
  Future<Report?> getReport(String id) async {
    try {
      final doc = await _reports.doc(id).get();
      return doc.exists ? Report.fromDoc(doc) : null;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return null;
      }
      rethrow;
    }
  }

  /// The reporter's phone and e-mail. Null unless you are the reporter, an
  /// admin, or someone whose claim on this report was approved.
  Future<ContactInfo?> getContact(String reportId) async {
    try {
      final doc = await _reports
          .doc(reportId)
          .collection(FirestorePaths.reportPrivate)
          .doc(FirestorePaths.contactDoc)
          .get();
      return doc.exists ? ContactInfo.fromDoc(doc) : null;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return null;
      }
      rethrow;
    }
  }

  /// Number of visible reports, for the dashboard.
  Future<int> countVisible({ReportType? type, ReportStatus? status}) {
    Query<Map<String, dynamic>> query = _reports.where('hidden', isEqualTo: false);
    if (type != null) {
      query = query.where('type', isEqualTo: type.value);
    }
    if (status != null) {
      query = query.where('status', isEqualTo: status.value);
    }
    return countDocuments(query);
  }

  /// Admin only: every report, hidden ones included.
  Stream<List<Report>> watchAllReports({
    bool? hidden,
    ReportType? type,
    int limit = 100,
  }) {
    Query<Map<String, dynamic>> query = _reports;
    if (hidden != null) {
      query = query.where('hidden', isEqualTo: hidden);
    }
    if (type != null) {
      query = query.where('type', isEqualTo: type.value);
    }
    return query
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Report.fromDoc).toList());
  }

  // ---------------------------------------------------------------------
  // Ranking of search results (pure functions, no Firebase needed)
  // ---------------------------------------------------------------------

  /// How many of the searched words the report's keywords contain.
  static int relevanceOf(Report report, List<String> tokens) {
    var matched = 0;
    for (final token in tokens) {
      if (report.keywords.contains(token)) {
        matched++;
      }
    }
    return matched;
  }

  /// Best matches first; equal scores keep "newest first". With no search
  /// words the list is returned unchanged (already newest first).
  static List<Report> rankByRelevance(List<Report> reports, List<String> tokens) {
    if (tokens.isEmpty) {
      return List<Report>.of(reports);
    }
    final scored = reports
        .map((report) => MapEntry<Report, int>(report, relevanceOf(report, tokens)))
        .toList();
    scored.sort((a, b) {
      final byScore = b.value.compareTo(a.value);
      if (byScore != 0) {
        return byScore;
      }
      return b.key.createdAt.compareTo(a.key.createdAt);
    });
    return scored.map((entry) => entry.key).toList();
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  /// Claims on a found report, read the way the security rules allow:
  /// with the report owner's id in the query.
  Future<List<Claim>> _claimsOnReport(Report report) async {
    final snapshot = await _claims
        .where('reportId', isEqualTo: report.id)
        .where('reportOwnerId', isEqualTo: report.userId)
        .get();
    return snapshot.docs.map(Claim.fromDoc).toList();
  }
}
