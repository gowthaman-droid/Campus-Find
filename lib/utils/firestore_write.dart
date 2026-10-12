import 'dart:async';

import 'package:flutter/foundation.dart';

import 'constants.dart';

/// Waits for a Firestore write to reach the server.
///
/// When the device is offline Firestore does not fail: it keeps the write on
/// the device and sends it later, so the Future of the write simply stays
/// pending. Waiting forever would freeze a screen, so this waits only
/// [timeout].
///
/// Returns true when the server confirmed the write and false when it is
/// still queued on the device. An error that arrives in time is thrown to the
/// caller. An error that arrives later (after the timeout) is only logged,
/// because nobody is waiting for it any more.
Future<bool> waitForServer(
  Future<void> write, {
  Duration? timeout,
  String label = 'write',
}) async {
  unawaited(
    write.then<void>(
      (_) {},
      onError: (Object error) {
        debugPrint('Firestore $label failed: $error');
      },
    ),
  );
  try {
    await write.timeout(timeout ?? AppConstants.writeTimeout);
    return true;
  } on TimeoutException {
    return false;
  }
}
