import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../utils/constants.dart';
import '../utils/firestore_count.dart';
import '../utils/formatters.dart';

/// Profiles in Firestore: `users/{uid}`.
class UserService {
  UserService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection(FirestorePaths.users);

  /// Saves the profile right after registration (role is always 'student').
  Future<void> createProfile({
    required String uid,
    required String name,
    required String email,
    required String phone,
  }) {
    return _users.doc(uid).set(
          AppUser.createMap(
            uid: uid,
            name: name,
            email: email,
            phone: Fmt.normalizePhone(phone),
          ),
        );
  }

  /// Null when the profile does not exist (yet).
  Future<AppUser?> getProfile(String uid) async {
    final doc = await _users.doc(uid).get();
    return doc.exists ? AppUser.fromDoc(doc) : null;
  }

  /// Live profile. Emits null while there is no profile document.
  Stream<AppUser?> watchProfile(String uid) {
    return _users.doc(uid).snapshots().map(
          (doc) => doc.exists ? AppUser.fromDoc(doc) : null,
        );
  }

  /// People may change only their name, phone and photo.
  Future<void> updateProfile({
    required String uid,
    required String name,
    required String phone,
    required String profileImage,
  }) {
    return _users.doc(uid).update(
          AppUser.updateMap(
            name: name,
            phone: Fmt.normalizePhone(phone),
            profileImage: profileImage,
          ),
        );
  }

  // ---------------------------------------------------------------------
  // Admin only. The security rules refuse these for everybody else.
  // ---------------------------------------------------------------------

  /// Newest accounts first.
  Stream<List<AppUser>> watchUsers({int limit = 200}) {
    return _users
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(AppUser.fromDoc).toList());
  }

  Future<int> countUsers() => countDocuments(_users);

  /// True when [error] means "you may not read this" (used by callers that
  /// want to treat that case as "nothing here").
  static bool isPermissionDenied(Object error) {
    return error is FirebaseException && error.code == 'permission-denied';
  }
}
