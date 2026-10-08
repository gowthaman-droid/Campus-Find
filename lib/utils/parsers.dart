import 'package:cloud_firestore/cloud_firestore.dart';

// Safe readers for Firestore data. A missing or wrongly typed field gives a
// sensible default instead of crashing a screen.

String readString(Map<String, dynamic> map, String key, {String fallback = ''}) {
  final value = map[key];
  return value is String ? value : fallback;
}

int readInt(Map<String, dynamic> map, String key, {int fallback = 0}) {
  final value = map[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return fallback;
}

bool readBool(Map<String, dynamic> map, String key, {bool fallback = false}) {
  final value = map[key];
  return value is bool ? value : fallback;
}

/// Reads a Firestore timestamp (or an ISO-8601 string) as a [DateTime].
/// A freshly written `serverTimestamp()` is still null on this device until
/// the server answers, so callers usually use [readDateTimeOr].
DateTime? readDateTime(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

DateTime readDateTimeOr(
  Map<String, dynamic> map,
  String key,
  DateTime fallback,
) {
  return readDateTime(map, key) ?? fallback;
}

List<String> readStringList(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return <String>[];
}

Map<String, dynamic> readMap(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return <String, dynamic>{};
}
