import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/enums.dart';
import '../models/picked_image.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../services/user_service.dart';
import '../utils/app_exception.dart';
import '../utils/firestore_write.dart';
import '../utils/formatters.dart';
import '../utils/validators.dart';
import 'provider_utils.dart';

/// Where the person is in the sign-in process. The start screen (Phase 10)
/// shows one screen per value.
enum AuthStatus {
  /// Waiting for Firebase to say who is signed in, or for the profile to load.
  initializing,

  /// Nobody is signed in: show login / register.
  signedOut,

  /// Signed in, but there is no profile document (registration was
  /// interrupted): ask for name and phone, then call `completeProfile`.
  needsProfile,

  /// Signed in, but the profile could not be read (see `profileError`):
  /// offer "Try again" (`retryProfile`) and "Log out".
  profileError,

  /// Signed in and the profile is loaded: show the app.
  signedIn,
}

/// Who is signed in, their profile, and whether they are an admin.
///
/// Everything else in the app depends on this provider: when the person
/// changes, the other providers (reports, claims, notifications, ...) are told
/// by the ProxyProviders in app_providers.dart and start or stop their live
/// Firestore listeners.
class AuthProvider extends ChangeNotifier with SafeNotifier {
  AuthProvider({
    required AuthService auth,
    required UserService users,
    required StorageService storage,
  })  : _auth = auth,
        _users = users,
        _storage = storage {
    _authSubscription = _auth.userChanges.listen(
      _onUserChanged,
      onError: _onAuthError,
    );
  }

  final AuthService _auth;
  final UserService _users;
  final StorageService _storage;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<AppUser?>? _profileSubscription;

  bool _authKnown = false;
  String? _uid;
  AppUser? _profile;
  bool _profileLoaded = false;
  String? _profileError;
  bool _isAdmin = false;
  bool _registering = false;
  bool _busy = false;

  // ---------------------------------------------------------------------
  // What the screens can read
  // ---------------------------------------------------------------------

  AuthStatus get status {
    if (!_authKnown) {
      return AuthStatus.initializing;
    }
    if (_uid == null) {
      return AuthStatus.signedOut;
    }
    if (_profile != null) {
      return AuthStatus.signedIn;
    }
    if (_profileError != null) {
      return AuthStatus.profileError;
    }
    if (!_profileLoaded || _registering) {
      return AuthStatus.initializing;
    }
    return AuthStatus.needsProfile;
  }

  /// Firebase user id of the signed-in person, or null.
  String? get uid => _uid;

  AppUser? get profile => _profile;

  /// True when the sign-in token carries the `admin` claim. Admin screens
  /// are only SHOWN when this is true; the real protection is the Firestore
  /// security rules, which check the same claim on the server.
  bool get isAdmin => _isAdmin;

  bool get isSignedIn => status == AuthStatus.signedIn;

  /// True while a login / register / profile action is running.
  bool get busy => _busy;

  /// Why the profile could not be read (only meaningful in `profileError`).
  String? get profileError => _profileError;

  /// E-mail of the Firebase account (also available without a profile).
  String? get accountEmail => _auth.currentUser?.email;

  // ---------------------------------------------------------------------
  // Following Firebase
  // ---------------------------------------------------------------------

  Future<void> _onUserChanged(User? user) async {
    _authKnown = true;
    final newUid = user?.uid;

    if (newUid != null && newUid == _uid) {
      // The same person: Firebase refreshed the token (about once an hour).
      // A new token may carry a changed admin claim, so read it again.
      await _refreshAdminFlag(force: false);
      return;
    }

    // A different person, or nobody: forget everything about the old one.
    await _profileSubscription?.cancel();
    _profileSubscription = null;
    _uid = newUid;
    _profile = null;
    _profileLoaded = false;
    _profileError = null;
    _isAdmin = false;
    notifyListeners();

    if (user == null) {
      return;
    }
    _listenToProfile(user.uid);
    await _refreshAdminFlag(force: true);
  }

  void _onAuthError(Object error) {
    debugPrint('Firebase sign-in state error: $error');
    _authKnown = true;
    notifyListeners();
  }

  void _listenToProfile(String uid) {
    _profileSubscription = _users.watchProfile(uid).listen(
          _onProfile,
          onError: _onProfileError,
        );
  }

  void _onProfile(AppUser? profile) {
    if (profile == null && _registering) {
      // The profile is being written right now; ignore the "not there yet".
      return;
    }
    _profile = profile;
    _profileLoaded = true;
    _profileError = null;
    notifyListeners();
  }

  void _onProfileError(Object error) {
    _profileError = friendlyError(error);
    _profileLoaded = true;
    notifyListeners();
  }

  Future<void> _refreshAdminFlag({required bool force}) async {
    final forUid = _uid;
    try {
      final admin = await _auth.isAdmin(forceRefresh: force);
      if (forUid != _uid) {
        return; // the person changed while we were waiting
      }
      if (admin != _isAdmin) {
        _isAdmin = admin;
        notifyListeners();
      }
    } catch (error) {
      debugPrint('Could not read the admin claim: $error');
    }
  }

  /// Asks Firebase for a brand-new token and reads the admin claim again.
  /// Useful right after someone was made admin.
  Future<void> refreshAdminAccess() => _refreshAdminFlag(force: true);

  /// Starts listening to the profile again after a `profileError`.
  Future<void> retryProfile() async {
    final uid = _uid;
    if (uid == null) {
      return;
    }
    await _profileSubscription?.cancel();
    _profileError = null;
    _profileLoaded = false;
    notifyListeners();
    _listenToProfile(uid);
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  Future<ActionResult<void>> signIn({
    required String email,
    required String password,
  }) {
    return _guard<void>(() async {
      final problem = Validators.email(email);
      if (problem != null) {
        return ActionResult<void>.failed(problem);
      }
      if (password.isEmpty) {
        return ActionResult<void>.failed('Password is required');
      }
      await _auth.signIn(email: email, password: password);
      return ActionResult<void>.ok();
    });
  }

  /// Creates the account AND the profile. If the profile cannot be saved the
  /// half-created account is removed again, so the person can simply retry
  /// with the same e-mail address.
  Future<ActionResult<void>> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) {
    return _guard<void>(() async {
      final problem = Validators.fullName(name) ??
          Validators.email(email) ??
          Validators.phone(phone) ??
          Validators.password(password);
      if (problem != null) {
        return ActionResult<void>.failed(problem);
      }

      _registering = true;
      notifyListeners();
      try {
        final user = await _auth.register(
          email: email,
          password: password,
          displayName: name,
        );
        try {
          await _users.createProfile(
            uid: user.uid,
            name: name,
            email: email,
            phone: phone,
          );
        } catch (error) {
          await _auth.deleteCurrentUser();
          return ActionResult<void>.failed(friendlyError(error));
        }
        // Show the new profile at once; the live listener replaces it with
        // the stored copy a moment later.
        _profile = _newProfile(
          uid: user.uid,
          name: name,
          email: email,
          phone: phone,
        );
        _profileLoaded = true;
        return ActionResult<void>.ok(message: 'Welcome to Campus Find!');
      } finally {
        _registering = false;
        notifyListeners();
      }
    });
  }

  /// For `AuthStatus.needsProfile`: saves the missing profile.
  Future<ActionResult<void>> completeProfile({
    required String name,
    required String phone,
  }) {
    return _guard<void>(() async {
      final uid = _uid;
      final email = _auth.currentUser?.email;
      if (uid == null || email == null) {
        return ActionResult<void>.failed('Please log in again.');
      }
      final problem = Validators.fullName(name) ?? Validators.phone(phone);
      if (problem != null) {
        return ActionResult<void>.failed(problem);
      }
      await _users.createProfile(
        uid: uid,
        name: name,
        email: email,
        phone: phone,
      );
      _profile = _newProfile(uid: uid, name: name, email: email, phone: phone);
      _profileLoaded = true;
      return ActionResult<void>.ok();
    });
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (error) {
      debugPrint('Sign-out failed: $error');
    }
  }

  /// Sends the "reset your password" e-mail. The answer is the same whether
  /// or not an account exists, so nobody can find out who is registered.
  Future<ActionResult<void>> sendPasswordReset(String email) {
    return _guard<void>(() async {
      final problem = Validators.email(email);
      if (problem != null) {
        return ActionResult<void>.failed(problem);
      }
      await _auth.sendPasswordReset(email);
      return ActionResult<void>.ok(
        message: 'If an account exists for that e-mail, a reset link is on its way.',
      );
    });
  }

  /// Changes name, phone and (optionally) the profile photo.
  Future<ActionResult<void>> updateProfile({
    required String name,
    required String phone,
    PickedImage? newPhoto,
    bool removePhoto = false,
  }) {
    return _guard<void>(() async {
      final current = _profile;
      if (current == null) {
        return ActionResult<void>.failed('Please log in again.');
      }
      final problem = Validators.fullName(name) ?? Validators.phone(phone);
      if (problem != null) {
        return ActionResult<void>.failed(problem);
      }

      var photoUrl = current.profileImage;
      UploadedImage? uploaded;
      if (newPhoto != null) {
        uploaded = await _storage.uploadProfileImage(
          uid: current.uid,
          image: newPhoto,
        );
        photoUrl = uploaded.url;
      } else if (removePhoto) {
        photoUrl = '';
      }

      final bool synced;
      try {
        synced = await waitForServer(
          _users.updateProfile(
            uid: current.uid,
            name: name,
            phone: phone,
            profileImage: photoUrl,
          ),
          label: 'profile update',
        );
      } catch (_) {
        if (uploaded != null) {
          await _storage.deleteQuietly(uploaded.path);
        }
        rethrow;
      }

      if (synced &&
          current.profileImage.isNotEmpty &&
          current.profileImage != photoUrl) {
        unawaited(_storage.deleteByUrlQuietly(current.profileImage));
      }
      return ActionResult<void>.ok(
        message: synced
            ? 'Profile updated.'
            : 'Saved on this phone. It will be sent when you are online again.',
        warning: !synced,
      );
    });
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  /// Runs [action] with the "busy" flag set. A second tap while busy is
  /// refused, and any error becomes a friendly [ActionResult].
  Future<ActionResult<T>> _guard<T>(
    Future<ActionResult<T>> Function() action,
  ) async {
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

  AppUser _newProfile({
    required String uid,
    required String name,
    required String email,
    required String phone,
  }) {
    return AppUser(
      uid: uid,
      name: name.trim(),
      email: email.trim(),
      phone: Fmt.normalizePhone(phone),
      role: UserRole.student,
      createdAt: DateTime.now(),
    );
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    unawaited(_profileSubscription?.cancel());
    super.dispose();
  }
}
