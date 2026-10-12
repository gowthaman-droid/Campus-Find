import 'package:flutter/foundation.dart';

import '../models/stats.dart';
import '../services/analytics_service.dart';
import '../utils/app_exception.dart';
import 'provider_utils.dart';

/// The analytics screen (admins only): totals, lost vs found, returned
/// items, pending claims, successful matches and the reports per category and
/// per campus area. Every number is counted by Firestore.
class AnalyticsProvider extends ChangeNotifier with SafeNotifier {
  AnalyticsProvider({required AnalyticsService analytics})
      : _analytics = analytics;

  final AnalyticsService _analytics;

  String? _uid;
  AnalyticsSummary _summary = const AnalyticsSummary.empty();
  bool _loading = false;
  String? _error;
  int _requestId = 0;

  AnalyticsSummary get summary => _summary;
  bool get loading => _loading;
  String? get error => _error;

  /// False until [load] has finished once.
  bool get hasData => _summary.generatedAt != null;

  /// Called by the ProxyProvider. A different person starts with no data.
  void bindUser(String? uid) {
    if (uid == _uid) {
      return;
    }
    _uid = uid;
    _requestId++;
    _summary = const AnalyticsSummary.empty();
    _loading = false;
    _error = null;
    notifyListenersSoon();
  }

  /// Counts everything again (about 26 small count queries).
  Future<void> load() async {
    if (_uid == null) {
      return;
    }
    final id = ++_requestId;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final summary = await _analytics.loadSummary();
      if (id != _requestId) {
        return;
      }
      _summary = summary;
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
