import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/picked_image.dart';
import '../utils/constants.dart';

/// Where an uploaded photo ended up.
class UploadedImage {
  const UploadedImage({required this.url, required this.path});

  /// Download URL, saved in `reports.imageUrl`.
  final String url;

  /// Storage path, saved in `reports.imagePath` (needed to delete the file).
  final String path;
}

/// Uploads and deletes photos in Cloud Storage for Firebase.
/// Folders must match storage.rules.
class StorageService {
  StorageService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  Future<UploadedImage> uploadReportImage({
    required String uid,
    required String reportId,
    required PickedImage image,
    void Function(double progress)? onProgress,
  }) {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.${image.extension}';
    return _upload(
      StoragePaths.reportImage(uid, reportId, fileName),
      image,
      onProgress,
    );
  }

  Future<UploadedImage> uploadProfileImage({
    required String uid,
    required PickedImage image,
    void Function(double progress)? onProgress,
  }) {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.${image.extension}';
    return _upload(StoragePaths.profileImage(uid, fileName), image, onProgress);
  }

  /// Deletes a file. A file that is already gone is not an error.
  Future<void> deleteByPath(String path) async {
    if (path.isEmpty) {
      return;
    }
    try {
      await _storage.ref(path).delete();
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') {
        return;
      }
      rethrow;
    }
  }

  /// Like [deleteByPath] but never throws. For clean-up after another step
  /// failed or succeeded; a left-over file is not worth bothering the person.
  Future<void> deleteQuietly(String path) async {
    try {
      await deleteByPath(path).timeout(const Duration(seconds: 10));
    } catch (error) {
      debugPrint('Could not delete the file $path: $error');
    }
  }

  /// Deletes a photo given its download URL (profile photos only store the
  /// URL). Never throws.
  Future<void> deleteByUrlQuietly(String url) async {
    if (url.isEmpty) {
      return;
    }
    try {
      await _storage
          .refFromURL(url)
          .delete()
          .timeout(const Duration(seconds: 10));
    } catch (error) {
      debugPrint('Could not delete the photo at $url: $error');
    }
  }

  Future<UploadedImage> _upload(
    String path,
    PickedImage image,
    void Function(double progress)? onProgress,
  ) async {
    final ref = _storage.ref(path);
    final task = ref.putData(
      image.bytes,
      SettableMetadata(contentType: image.contentType),
    );
    StreamSubscription<TaskSnapshot>? progressSubscription;
    if (onProgress != null) {
      progressSubscription = task.snapshotEvents.listen((snapshot) {
        if (snapshot.totalBytes > 0) {
          onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
        }
      });
    }
    try {
      await task.timeout(
        AppConstants.uploadTimeout,
        onTimeout: () {
          unawaited(task.cancel());
          throw TimeoutException('The photo upload took too long.');
        },
      );
      final url = await ref.getDownloadURL();
      return UploadedImage(url: url, path: path);
    } finally {
      await progressSubscription?.cancel();
    }
  }
}
