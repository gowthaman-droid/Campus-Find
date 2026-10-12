import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../utils/app_exception.dart';

/// Everything about signing in: a thin wrapper around Firebase Authentication.
/// Errors are left as they are; screens turn them into friendly text with
/// `friendlyError(error)`.
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  /// Emits the signed-in user, or null after logout. Also fires again when the
  /// sign-in token is refreshed (for example after an admin claim changed).
  Stream<User?> get userChanges => _auth.idTokenChanges();

  User? get currentUser => _auth.currentUser;

  String? get currentUid => _auth.currentUser?.uid;

  /// Creates the Firebase account. The Firestore profile is written
  /// afterwards by UserService.
  Future<User> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw const AppException(
        'Could not create the account. Please try again.',
      );
    }
    final name = displayName?.trim() ?? '';
    if (name.isNotEmpty) {
      try {
        await user.updateDisplayName(name);
      } catch (error) {
        // Not important: the real name lives in the Firestore profile.
        debugPrint('Could not set the display name: $error');
      }
    }
    return user;
  }

  Future<User> signIn({required String email, required String password}) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw const AppException('Could not log in. Please try again.');
    }
    return user;
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Removes the account that was just created. Used when registration fails
  /// half-way (account created, profile not saved) so the person can retry
  /// with the same e-mail address.
  Future<void> deleteCurrentUser() async {
    try {
      await _auth.currentUser?.delete();
    } catch (error) {
      debugPrint('Could not delete the half-created account: $error');
    }
  }

  /// The sign-in token sent to the Python service. [forceRefresh] asks
  /// Firebase for a brand-new token.
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }
    return user.getIdToken(forceRefresh);
  }

  /// True when the sign-in token carries the custom claim `admin: true`.
  /// This is the same signal the security rules use. Use
  /// `forceRefresh: true` right after login so a freshly granted claim
  /// is picked up.
  Future<bool> isAdmin({bool forceRefresh = false}) async {
    final token = await getIdToken(forceRefresh: forceRefresh);
    if (token == null) {
      return false;
    }
    return claimsFromToken(token)['admin'] == true;
  }

  /// Reads the claims out of a Firebase ID token (a JWT: header.payload.signature).
  /// Only used to decide which screens to show; real protection is the
  /// security rules, which check the token on Google's servers.
  static Map<String, dynamic> claimsFromToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      return <String, dynamic>{};
    }
    try {
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (error) {
      debugPrint('Could not read the token claims: $error');
    }
    return <String, dynamic>{};
  }
}
