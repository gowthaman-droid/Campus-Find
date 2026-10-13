import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/enums.dart';
import '../models/report.dart';
import '../models/search_filters.dart';
import '../services/report_service.dart';
import '../utils/app_exception.dart';
import 'provider_utils.dart';

/// The Search screen: filters, results and "load more".
class SearchProvider extends ChangeNotifier with SafeNotifier {
  SearchProvider({
    required ReportService reports,
    Duration debounce = const Duration(milliseconds: 400),
  })  : _reports = reports,
        _debounceDuration = debounce;

  final ReportService _reports;
  final Duration _debounceDuration;

  String? _uid;
  SearchFilters _filters = const SearchFilters();
  List<Report> _results = const <Report>[];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _loadedOnce = false;
  String? _error;
  int _requestId = 0;
  Timer? _debounce;

  SearchFilters get filters => _filters;
  List<Report> get results => _results;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;

  bool get showsEmptyState =>
      _loadedOnce && !_loading && _error == null && _results.isEmpty;

  void bindUser(String? uid) {
    if (uid == _uid) {
      return;
    }
    _uid = uid;
    _debounce?.cancel();
    _requestId++;
    _filters = const SearchFilters();
    _results = const <Report>[];
    _cursor = null;
    _hasMore = false;
    _loading = false;
    _loadingMore = false;
    _loadedOnce = false;
    _error = null;
    notifyListenersSoon();
  }

  Future<void> ensureLoaded() async {
    if (_uid == null || _loadedOnce) {
      return;
    }
    await search();
  }

  void setText(String text) {
    final before = _filters.tokens;
    _filters = _filters.copyWith(query: text);
    notifyListeners();
    if (listEquals(before, _filters.tokens)) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      unawaited(search());
    });
  }

  void setType(ReportType? type) {
    _apply(_filters.copyWith(type: type, clearType: type == null));
  }

  void setStatus(ReportStatus? status) {
    _apply(_filters.copyWith(status: status, clearStatus: status == null));
  }

  void setCategory(String? category) {
    _apply(_filters.copyWith(category: category, clearCategory: category == null));
  }

  void setLocation(String? location) {
    _apply(_filters.copyWith(location: location, clearLocation: location == null));
  }

  void clearFilters() {
    _apply(const SearchFilters());
  }

  void _apply(SearchFilters next) {
    if (next == _filters) {
      return;
    }
    _filters = next;
    unawaited(search());
  }

  Future<void> search() async {
    if (_uid == null) {
      return;
    }
    _debounce?.cancel();
    final id = ++_requestId;
    final filters = _filters;
    _loadedOnce = true;
    _loading = true;
    _loadingMore = false;
    _error = null;
    notifyListeners();

    try {
      final page = await _reports.fetchPage(filters);
      if (id != _requestId) {
        return;
      }
      _results = ReportService.rankByRelevance(page.items, filters.tokens);
      _cursor = page.cursor;
      _hasMore = page.hasMore;
    } catch (error) {
      if (id != _requestId) {
        return;
      }
      _results = const <Report>[];
      _cursor = null;
      _hasMore = false;
      _error = friendlyError(error);
    } finally {
      if (id == _requestId) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    final cursor = _cursor;
    if (_uid == null || !_hasMore || _loading || _loadingMore || cursor == null) {
      return;
    }
    final id = _requestId;
    final filters = _filters;
    _loadingMore = true;
    notifyListeners();

    try {
      final page = await _reports.fetchPage(filters, startAfter: cursor);
      if (id != _requestId || filters != _filters) {
        return;
      }
      final known = _results.map((report) => report.id).toSet();
      final fresh = page.items.where((report) => !known.contains(report.id));
      _results = <Report>[..._results, ...fresh];
      _cursor = page.cursor;
      _hasMore = page.hasMore;
    } catch (error) {
      if (id != _requestId) {
        return;
      }
      _error = friendlyError(error);
    } finally {
      if (id == _requestId) {
        _loadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() => search();

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}