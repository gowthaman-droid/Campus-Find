import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:http/http.dart' as http;

/// An error whose [message] is already safe and friendly to show to a person.
class AppException implements Exception {
  const AppException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// An error answer from the Python matching service.
class ApiException extends AppException {
  const ApiException(
    super.message, {
    required this.statusCode,
    super.code,
    this.details,
  });

  /// HTTP status. 0 means "no answer at all" (offline, refused, timeout).
  final int statusCode;
  final Object? details;

  bool get isServiceUnavailable => statusCode == 0 || statusCode == 503;
  bool get isConflict => statusCode == 409;
  bool get isUnauthorized => statusCode == 401;
}

/// Turns ANY error into a short, friendly sentence.
/// Raw technical messages are never shown to people.
String friendlyError(Object error) {
  if (error is AppException) {
    return error.message;
  }
  if (error is FirebaseAuthException) {
    return _authMessage(error.code);
  }
  if (error is FirebaseException) {
    return _firebaseMessage(error);
  }
  if (error is TimeoutException) {
    return 'The request took too long. Please check your connection and try again.';
  }
  if (error is http.ClientException) {
    return 'Cannot reach the Campus Find service. Please check your internet connection and try again.';
  }
  if (error is FormatException) {
    return 'The server sent a reply the app could not read. Please try again later.';
  }
  return 'Something went wrong. Please try again.';
}

/// True when the problem is "no connection / service down" rather than a
/// mistake in the data. Used to decide between "retry later" and "fix input".
bool isConnectivityProblem(Object error) {
  if (error is TimeoutException || error is http.ClientException) {
    return true;
  }
  if (error is ApiException) {
    return error.isServiceUnavailable;
  }
  if (error is FirebaseException) {
    return error.code == 'unavailable' ||
        error.code == 'network-request-failed' ||
        error.code == 'deadline-exceeded';
  }
  return false;
}

String _authMessage(String code) {
  switch (code) {
    case 'invalid-email':
      return 'That e-mail address is not valid.';
    case 'user-disabled':
      return 'This account has been disabled. Please contact the campus admin.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'E-mail or password is incorrect.';
    case 'email-already-in-use':
      return 'An account with this e-mail already exists. Try logging in instead.';
    case 'weak-password':
      return 'Please choose a stronger password (at least 8 characters).';
    case 'too-many-requests':
      return 'Too many attempts. Please wait a few minutes and try again.';
    case 'network-request-failed':
      return 'No internet connection. Please check your network and try again.';
    case 'operation-not-allowed':
      return 'E-mail/password sign-in is not enabled for this project.';
    case 'requires-recent-login':
      return 'Please log in again to continue.';
    default:
      return 'Could not complete that. Please try again.';
  }
}

String _firebaseMessage(FirebaseException error) {
  final code = error.code;
  if (error.plugin == 'firebase_storage') {
    switch (code) {
      case 'unauthorized':
        return 'You are not allowed to upload this image.';
      case 'canceled':
        return 'The upload was cancelled.';
      case 'retry-limit-exceeded':
      case 'unavailable':
        return 'The image upload failed because the connection is poor. Please try again.';
      case 'quota-exceeded':
        return 'The image storage limit has been reached. Please contact the admin.';
      case 'object-not-found':
        return 'The image could not be found.';
      default:
        return 'The image could not be uploaded. Please try again.';
    }
  }
  switch (code) {
    case 'permission-denied':
      return 'You do not have permission to do that.';
    case 'unavailable':
    case 'network-request-failed':
      return 'Cannot reach the server. Check your internet connection and try again.';
    case 'deadline-exceeded':
      return 'The request took too long. Please try again.';
    case 'not-found':
      return 'That item no longer exists.';
    case 'already-exists':
      return 'That already exists.';
    case 'aborted':
    case 'cancelled':
      return 'The action was interrupted. Please try again.';
    case 'failed-precondition':
      return 'This search needs a database index that is not ready yet. '
          'Please try again in a few minutes, or ask the admin to deploy the indexes.';
    case 'unauthenticated':
      return 'Your session has expired. Please log in again.';
    default:
      return 'Something went wrong while talking to the database. Please try again.';
  }
}
