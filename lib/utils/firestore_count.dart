import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show MissingPluginException;

/// Counts the documents that match [query].
///
/// Normally this uses Firestore's server-side `count()`, which reads almost
/// nothing and is very cheap. If a platform build does not support aggregate
/// queries (some desktop builds), it falls back to reading up to
/// [fallbackLimit] documents and counting them on the device.
Future<int> countDocuments(
  Query<Map<String, dynamic>> query, {
  int fallbackLimit = 1000,
}) async {
  try {
    final snapshot = await query.count().get();
    return snapshot.count ?? 0;
  } on UnimplementedError {
    return _countByReading(query, fallbackLimit);
  } on UnsupportedError {
    return _countByReading(query, fallbackLimit);
  } on MissingPluginException {
    return _countByReading(query, fallbackLimit);
  } on FirebaseException catch (error) {
    if (error.code == 'unimplemented') {
      return _countByReading(query, fallbackLimit);
    }
    rethrow;
  }
}

Future<int> _countByReading(
  Query<Map<String, dynamic>> query,
  int limit,
) async {
  final snapshot = await query.limit(limit).get();
  return snapshot.size;
}
