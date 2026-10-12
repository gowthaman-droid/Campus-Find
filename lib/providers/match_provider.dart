import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/match_record.dart';
import '../services/match_service.dart';
import '../utils/app_exception.dart';
import 'provider_utils.dart';

/// My active matches (potential lost/found pairs), as a live list.
/// The matches themselves are created by the Python service; the app only
/// shows them.
class MatchProvider extends ChangeNotifier with SafeNotifier {
  MatchProvider({required MatchService matches}) : _service = matches;

  final MatchService _service;

  String? _uid;
  StreamSubscription<List<MatchRecord>>? _subscription;
  List<MatchRecord> _items = const <MatchRecord>[];
  bool _loading = false;
  String? _error;

  /// All my active matches (newest first, as stored).
  List<MatchRecord> get matches => _items;

  /// The number on the dashboard card "Potential matches".
  int get count => _items.length;

  bool get hasStrongMatch => _items.any((match) => match.strong);

  bool get loading => _loading;
  String? get error => _error;

  /// My matches that involve one report, strongest first.
  List<MatchRecord> forReport(String reportId) {
    final list = _items
        .where(
          (match) =>
              match.lostReportId == reportId || match.foundReportId == reportId,
        )
        .toList();
    list.sort((a, b) => b.score.compareTo(a.score));
    return list;
  }

  /// The best score of a report (0 when it has no match).
  int bestScoreFor(String reportId) {
    final list = forReport(reportId);
    return list.isEmpty ? 0 : list.first.score;
  }

  /// Called by the ProxyProvider whenever the sign-in state changes.
  void bindUser(String? uid) {
    if (uid == _uid) {
      return;
    }
    _uid = uid;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _items = const <MatchRecord>[];
    _error = null;
    _loading = false;

    if (uid != null) {
      _loading = true;
      _subscription = _service.watchMyMatches(uid).listen(
        (matches) {
          _items = matches;
          _loading = false;
          _error = null;
          notifyListeners();
        },
        onError: (Object error) {
          _error = friendlyError(error);
          _loading = false;
          notifyListeners();
        },
      );
    }
    notifyListenersSoon();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
