import 'package:flutter/foundation.dart';

import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/claim.dart';
import '../models/enums.dart';
import '../models/match_record.dart';
import '../models/report.dart';
import '../models/stats.dart';
import '../services/analytics_service.dart';
import '../services/backend_api_service.dart';
import '../services/claim_service.dart';
import '../services/match_service.dart';
import '../services/notification_service.dart';
import '../services/report_service.dart';
import '../services/user_service.dart';
import '../utils/app_exception.dart';
import '../utils/constants.dart';
import '../utils/validators.dart';
import 'provider_utils.dart';

/// Everything only admins do: the dashboard numbers, live lists of ALL users,
/// reports, claims, matches and notifications, and the admin actions.
///
/// IMPORTANT: this provider refuses to work for people who are not admins, but
/// that is only a convenience for the screens. The real protection is the
/// Firestore security rules and the Python service, which both check the
/// `admin` claim on the server. A non-admin who calls these methods anyway gets
/// "permission denied" from Firebase.
///
/// Reviewing claims as an admin uses ClaimProvider (approve / reject /
/// complete): the rules let admins review any claim.
class AdminProvider extends ChangeNotifier with SafeNotifier {
  AdminProvider({
    required AnalyticsService analytics,
    required UserService users,
    required ReportService reports,
    required ClaimService claims,
    required MatchService matches,
    required NotificationService notifications,
    required BackendApiService api,
  })  : _analytics = analytics,
        _users = users,
        _reports = reports,
        _claims = claims,
        _matches = matches,
        _notifications = notifications,
        _api = api;

  final AnalyticsService _analytics;
  final UserService _users;
  final ReportService _reports;
  final ClaimService _claims;
  final MatchService _matches;
  final NotificationService _notifications;
  final BackendApiService _api;

  String? _uid;
  bool _isAdmin = false;
  AdminStats _stats = const AdminStats.empty();
  bool _loadingStats = false;
  String? _statsError;
  bool _busy = false;
  int _requestId = 0;

  bool get isAdmin => _isAdmin;
  AdminStats get stats => _stats;
  bool get loadingStats => _loadingStats;
  String? get statsError => _statsError;

  /// True while an admin action is running (disable the buttons).
  bool get busy => _busy;

  /// Called by the ProxyProvider whenever the sign-in state changes.
  void bindAdmin({required String? uid, required bool isAdmin}) {
    final admin = isAdmin && uid != null;
    if (uid == _uid && admin == _isAdmin) {
      return;
    }
    final changed = uid != _uid || !admin;
    _uid = uid;
    _isAdmin = admin;
    if (changed) {
      _requestId++;
      _stats = const AdminStats.empty();
      _statsError = null;
      _loadingStats = false;
    }
    notifyListenersSoon();
  }

  /// The six numbers of the admin dashboard.
  Future<void> loadStats() async {
    if (!_isAdmin) {
      return;
    }
    final id = ++_requestId;
    _loadingStats = true;
    _statsError = null;
    notifyListeners();

    try {
      final stats = await _analytics.loadAdminStats();
      if (id != _requestId) {
        return;
      }
      _stats = stats;
    } catch (error) {
      if (id != _requestId) {
        return;
      }
      _statsError = friendlyError(error);
    } finally {
      if (id == _requestId) {
        _loadingStats = false;
        notifyListeners();
      }
    }
  }

  // ---------------------------------------------------------------------
  // Live lists (use them with a StreamBuilder). Empty for non-admins.
  // ---------------------------------------------------------------------

  Stream<List<AppUser>> watchUsers() {
    return _isAdmin ? _users.watchUsers() : const Stream<List<AppUser>>.empty();
  }

  /// All reports, hidden ones included. [hidden]: true = only hidden ones,
  /// false = only visible ones, null = all.
  Stream<List<Report>> watchReports({bool? hidden, ReportType? type}) {
    if (!_isAdmin) {
      return const Stream<List<Report>>.empty();
    }
    return _reports.watchAllReports(hidden: hidden, type: type);
  }

  Stream<List<Claim>> watchClaims({ClaimStatus? status}) {
    if (!_isAdmin) {
      return const Stream<List<Claim>>.empty();
    }
    return _claims.watchAllClaims(status: status);
  }

  Stream<List<MatchRecord>> watchMatches({MatchRecordStatus? status}) {
    if (!_isAdmin) {
      return const Stream<List<MatchRecord>>.empty();
    }
    return _matches.watchAllMatches(status: status);
  }

  Stream<List<AppNotification>> watchNotifications() {
    return _isAdmin
        ? _notifications.watchAll()
        : const Stream<List<AppNotification>>.empty();
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  /// Makes someone an admin or a student again (done by the Python service,
  /// which sets the sign-in claim). The person must log out and in again.
  Future<ActionResult<void>> setUserRole(AppUser user, UserRole role) {
    return _run<void>(() async {
      if (user.uid == _uid && role != UserRole.admin) {
        return ActionResult<void>.failed(
          'You cannot remove your own admin access.',
        );
      }
      await _api.setUserRole(user.uid, role.value);
      return ActionResult<void>.ok(
        message: '${user.name} is now ${role.label.toLowerCase()}. '
            'The change applies after they log out and in again.',
      );
    });
  }

  /// Blocks or unblocks an account. A blocked person cannot log in again.
  Future<ActionResult<void>> setUserDisabled(AppUser user, bool disabled) {
    return _run<void>(() async {
      if (user.uid == _uid && disabled) {
        return ActionResult<void>.failed('You cannot block your own account.');
      }
      await _api.setUserDisabled(user.uid, disabled);
      return ActionResult<void>.ok(
        message: disabled
            ? '${user.name} was blocked.'
            : '${user.name} was unblocked.',
      );
    });
  }

  /// Hides an inappropriate report from everybody except its owner.
  Future<ActionResult<void>> hideReport(Report report, {String reason = ''}) {
    return _run<void>(() async {
      final admin = _uid;
      if (admin == null) {
        return ActionResult<void>.failed('Please log in first.');
      }
      await _reports.setHidden(
        reportId: report.id,
        hidden: true,
        adminUid: admin,
        reason: reason,
      );
      return ActionResult<void>.ok(message: 'The report is now hidden.');
    });
  }

  Future<ActionResult<void>> unhideReport(Report report) {
    return _run<void>(() async {
      final admin = _uid;
      if (admin == null) {
        return ActionResult<void>.failed('Please log in first.');
      }
      await _reports.setHidden(
        reportId: report.id,
        hidden: false,
        adminUid: admin,
      );
      return ActionResult<void>.ok(message: 'The report is visible again.');
    });
  }

  /// Permanently deletes a report (use hide for reversible moderation).
  Future<ActionResult<void>> deleteReport(Report report) {
    return _run<void>(() async {
      final admin = _uid;
      if (admin == null) {
        return ActionResult<void>.failed('Please log in first.');
      }
      await _reports.deleteReport(report, actorUid: admin, asAdmin: true);
      return ActionResult<void>.ok(message: 'The report was deleted.');
    });
  }

  Future<ActionResult<void>> deleteMatch(MatchRecord match) {
    return _run<void>(() async {
      await _matches.deleteMatch(match.id);
      return ActionResult<void>.ok(message: 'The match was removed.');
    });
  }

  /// A message to one person ([to]) or to everybody (leave [to] empty).
  Future<ActionResult<BroadcastResult>> sendMessage({
    required String title,
    required String body,
    AppUser? to,
  }) {
    return _run<BroadcastResult>(() async {
      final checkTitle = Validators.lengthBetween(
        'Title',
        1,
        AppConstants.notificationTitleMax,
      );
      final checkBody = Validators.lengthBetween(
        'Message',
        1,
        AppConstants.notificationBodyMax,
      );
      final problem = checkTitle(title) ?? checkBody(body);
      if (problem != null) {
        return ActionResult<BroadcastResult>.failed(problem);
      }
      final result = await _api.sendAdminMessage(
        title: title,
        body: body,
        userId: to?.uid,
      );
      final target = to == null ? 'everybody' : to.name;
      return ActionResult<BroadcastResult>.ok(
        message: 'Message sent to $target (${result.recipients} recipient(s)).',
        warning: !result.pushed,
        data: result,
      );
    });
  }

  /// Runs the matching again for reports whose matching is pending or failed.
  Future<ActionResult<RematchResult>> rematchPending({int limit = 50}) {
    return _run<RematchResult>(() async {
      final result = await _api.rematch(limit: limit);
      return ActionResult<RematchResult>.ok(
        message: 'Matching ran for ${result.processed} report(s): '
            '${result.succeeded} succeeded, ${result.failed} failed.',
        warning: result.failed > 0,
        data: result,
      );
    });
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  Future<ActionResult<T>> _run<T>(
    Future<ActionResult<T>> Function() action,
  ) async {
    if (!_isAdmin) {
      return ActionResult<T>.failed('Admin access is required.');
    }
    if (_busy) {
      return ActionResult<T>.failed('Please wait a moment and try again.');
    }
    _busy = true;
    notifyListeners();
    try {
      return await action();
    } catch (error) {
      return ActionResult<T>.failed(friendlyError(error));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
