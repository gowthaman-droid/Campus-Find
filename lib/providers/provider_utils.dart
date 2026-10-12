import 'dart:async';

import 'package:flutter/foundation.dart';

/// The result of something a person asked for (log in, send a claim, ...).
///
/// Providers never throw errors at the screen. They return an ActionResult
/// whose [message] is always a friendly sentence that can be shown as it is,
/// for example in a SnackBar:
///
/// ```dart
/// final result = await context.read<ClaimProvider>().submitClaim(...);
/// if (!result.success) showError(result.message!);
/// ```
class ActionResult<T> {
  const ActionResult._({
    required this.success,
    this.message,
    this.isWarning = false,
    this.data,
  });

  /// It worked. [message] is optional text to show. Set [warning] when it
  /// worked but something minor did not (for example a notification could not
  /// be sent), so the screen can use a different colour.
  factory ActionResult.ok({String? message, bool warning = false, T? data}) {
    return ActionResult<T>._(
      success: true,
      message: message,
      isWarning: warning,
      data: data,
    );
  }

  /// It did not work. [message] says why, in plain words.
  factory ActionResult.failed(String message) {
    return ActionResult<T>._(success: false, message: message);
  }

  final bool success;
  final String? message;
  final bool isWarning;

  /// Extra information of the action (for example the new report's id).
  final T? data;
}

/// Makes a ChangeNotifier safe to use from asynchronous code.
///
///  * After `dispose()` nothing is notified any more, so a late answer from
///    Firebase cannot crash the app.
///  * [notifyListenersSoon] is for state changes that happen while Flutter is
///    building widgets (inside a ProxyProvider `update`), where notifying
///    immediately is not allowed.
mixin SafeNotifier on ChangeNotifier {
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  void notifyListenersSoon() {
    scheduleMicrotask(notifyListeners);
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
