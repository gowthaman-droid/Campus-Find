import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/parsers.dart';
import 'enums.dart';

/// One person's profile: the document `users/{uid}`.
class AppUser {
  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.createdAt,
    this.profileImage = '',
    this.updatedAt,
    this.disabled = false,
  });

  final String uid;
  final String name;
  final String email;
  final String phone;

  /// Display copy of the admin flag. Security rules and admin screens use the
  /// `admin` claim in the sign-in token, never this field.
  final UserRole role;

  final DateTime createdAt;
  final String profileImage;
  final DateTime? updatedAt;
  final bool disabled;

  bool get hasProfileImage => profileImage.isNotEmpty;

  /// "Asha Kumar" -> "Asha"
  String get firstName {
    final text = name.trim();
    if (text.isEmpty) {
      return 'there';
    }
    return text.split(RegExp(r'\s+')).first;
  }

  factory AppUser.fromMap(String id, Map<String, dynamic> map) {
    return AppUser(
      uid: readString(map, 'uid', fallback: id),
      name: readString(map, 'name'),
      email: readString(map, 'email'),
      phone: readString(map, 'phone'),
      role: UserRole.fromValue(readString(map, 'role')),
      createdAt: readDateTimeOr(map, 'createdAt', DateTime.now()),
      profileImage: readString(map, 'profileImage'),
      updatedAt: readDateTime(map, 'updatedAt'),
      disabled: readBool(map, 'disabled'),
    );
  }

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AppUser.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});
  }

  /// The exact map written at registration. The 7 keys match
  /// `validNewProfile` in firestore.rules (role must be 'student').
  static Map<String, dynamic> createMap({
    required String uid,
    required String name,
    required String email,
    required String phone,
  }) {
    return <String, dynamic>{
      'uid': uid,
      'name': name.trim(),
      'email': email.trim(),
      'phone': phone,
      'role': UserRole.student.value,
      'createdAt': FieldValue.serverTimestamp(),
      'profileImage': '',
    };
  }

  /// What a person may change later: name, phone and photo only.
  static Map<String, dynamic> updateMap({
    required String name,
    required String phone,
    required String profileImage,
  }) {
    return <String, dynamic>{
      'name': name.trim(),
      'phone': phone,
      'profileImage': profileImage,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
