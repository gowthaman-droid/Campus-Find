import 'package:flutter/foundation.dart';

import '../models/enums.dart';
import '../models/stats.dart';
import '../services/match_service.dart';
import '../services/report_service.dart';
import '../utils/app_exception.dart';
import 'provider_utils.dart';

/// The four numbers on the student home screen: lost items, found items,
/// returned items and my potential matches. All of them are real counts from
/// Firestore, loaded with `count()` queries.
class DashboardProvider extends ChangeNotifier with SafeNotifier {
  DashboardProvider({
    required ReportService reports,
    required MatchService matches,
  })  : _reports = reports,
        _matches = matches;

  final ReportService _reports;
  final MatchService _matches;

  String? _uid;
  DashboardStats _stats = const DashboardStats.empty();
  bool _loading = false;
  String? _error;
  int _requestId = 0;

  DashboardStats get stats => _stats;
  bool get loading => _loading;
  String? get error => _error;

  /// Called by the ProxyProvider whenever the sign-in state changes.
  void bindUser(String? uid) {
    if (uid == _uid) {
      return;
    }
    _uid = uid;
    _requestId++; // answers still on their way belong to the old person
    _stats = const DashboardStats.empty();
    _loading = false;
    _error = null;
    notifyListenersSoon();
  }

  /// Loads the numbers. Call it when the home screen opens and for
  /// pull-to-refresh.
  Future<void> refresh() async {
    final uid = _uid;
    if (uid == null) {
      return;
    }
    final id = ++_requestId;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final counts = await Future.wait<int>(<Future<int>>[
        _reports.countVisible(type: ReportType.lost, status: ReportStatus.active),
        _reports.countVisible(type: ReportType.found, status: ReportStatus.active),
        _reports.countVisible(status: ReportStatus.returned),
        _matches.countMyActive(uid),
      ]);
      if (id != _requestId) {
        return;
      }
      _stats = DashboardStats(
        lostItems: counts[0],
        foundItems: counts[1],
        returnedItems: counts[2],
        potentialMatches: counts[3],
      );
    } catch (error) {
      if (id != _requestId) {
        return;
      }
      _error = friendlyError(error);
    } finally {
      if (id == _requestId) {
        _loading = false;
        notifyListeners();
      }
    }
  }
}
