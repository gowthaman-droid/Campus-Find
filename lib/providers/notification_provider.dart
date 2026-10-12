import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_notification.dart';
import '../services/notification_service.dart';
import '../utils/app_exception.dart';
import 'provider_utils.dart';

/// The in-app notification list and the unread badge, both live.
///
/// Notifications are created by the Python service. This provider only reads
/// them and lets the person mark them as read or delete them.
class NotificationProvider extends ChangeNotifier with SafeNotifier {
  NotificationProvider({required NotificationService notifications})
      : _service = notifications;

  final NotificationService _service;

  String? _uid;
  StreamSubscription<List<AppNotification>>? _itemsSubscription;
  StreamSubscription<int>? _unreadSubscription;
  List<AppNotification> _items = const <AppNotification>[];
  int _unread = 0;
  bool _loading = false;
  String? _error;

  List<AppNotification> get items => _items;

  /// Unread notifications (counted up to 99).
  int get unreadCount => _unread;

  /// "3", or "99+" when there are 99 or more.
  String get unreadLabel => _unread >= 99 ? '99+' : '$_unread';

  bool get hasUnread => _unread > 0;
  bool get loading => _loading;
  String? get error => _error;

  /// Called by the ProxyProvider whenever the sign-in state changes.
  void bindUser(String? uid) {
    if (uid == _uid) {
      return;
    }
    _uid = uid;
    unawaited(_itemsSubscription?.cancel());
    unawaited(_unreadSubscription?.cancel());
    _itemsSubscription = null;
    _unreadSubscription = null;
    _items = const <AppNotification>[];
    _unread = 0;
    _error = null;
    _loading = false;

    if (uid != null) {
      _loading = true;
      _itemsSubscription = _service.watchMine(uid).listen(
        (items) {
          _items = items;
          _loading = false;
          _error = null;
          notifyListeners();
        },
        onError: _onError,
      );
      _unreadSubscription = _service.watchUnreadCount(uid).listen(
        (count) {
          _unread = count;
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

  Future<ActionResult<void>> markRead(AppNotification notification) {
    if (notification.read) {
      return Future<ActionResult<void>>.value(ActionResult<void>.ok());
    }
    return _run(() => _service.markRead(notification.id));
  }

  Future<ActionResult<void>> markAllRead() {
    final uid = _uid;
    if (uid == null) {
      return Future<ActionResult<void>>.value(
        ActionResult<void>.failed('Please log in first.'),
      );
    }
    return _run(() => _service.markAllRead(uid));
  }

  Future<ActionResult<void>> remove(AppNotification notification) {
    return _run(() => _service.delete(notification.id));
  }

  Future<ActionResult<void>> clearAll() {
    final uid = _uid;
    if (uid == null) {
      return Future<ActionResult<void>>.value(
        ActionResult<void>.failed('Please log in first.'),
      );
    }
    return _run(() => _service.deleteAllMine(uid));
  }

  Future<ActionResult<void>> _run(Future<Object?> Function() action) async {
    try {
      await action();
      return ActionResult<void>.ok();
    } catch (error) {
      return ActionResult<void>.failed(friendlyError(error));
    }
  }

  @override
  void dispose() {
    unawaited(_itemsSubscription?.cancel());
    unawaited(_unreadSubscription?.cancel());
    super.dispose();
  }
}
