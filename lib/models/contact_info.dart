import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/parsers.dart';

/// The reporter's private contact details: `reports/{id}/private/contact`.
/// Only the reporter, an admin, or a person with an approved claim can read it.
class ContactInfo {
  const ContactInfo({
    required this.userId,
    required this.phone,
    required this.email,
    this.updatedAt,
  });

  final String userId;
  final String phone;
  final String email;
  final DateTime? updatedAt;

  factory ContactInfo.fromMap(Map<String, dynamic> map) {
    return ContactInfo(
      userId: readString(map, 'userId'),
      phone: readString(map, 'phone'),
      email: readString(map, 'email'),
      updatedAt: readDateTime(map, 'updatedAt'),
    );
  }

  factory ContactInfo.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return ContactInfo.fromMap(doc.data() ?? const <String, dynamic>{});
  }

  /// The 4 keys required by firestore.rules for `private/contact`.
  static Map<String, dynamic> writeMap({
    required String userId,
    required String phone,
    required String email,
  }) {
    return <String, dynamic>{
      'userId': userId,
      'phone': phone,
      'email': email.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
