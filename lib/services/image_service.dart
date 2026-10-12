import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';

import '../models/picked_image.dart';
import '../utils/app_exception.dart';
import '../utils/constants.dart';

/// Lets the person choose a photo and checks that it really is a usable image.
class ImageService {
  ImageService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// The Windows file dialog has no camera. Offer the camera on Android only.
  static bool get canUseCamera => AppConfig.isAndroid;

  /// Opens the gallery / file dialog / camera.
  /// Returns null when the person cancels. Throws an [AppException] with a
  /// friendly message when the file is not usable.
  Future<PickedImage?> pick({ImageSource source = ImageSource.gallery}) async {
    XFile? file;
    try {
      file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
    } on PlatformException catch (error) {
      final what = source == ImageSource.camera ? 'the camera' : 'your photos';
      throw AppException(
        'Could not open $what. Please check that Campus Find is allowed to '
        'use it and try again.',
        code: error.code,
      );
    }
    if (file == null) {
      return null; // cancelled
    }
    final bytes = await file.readAsBytes();
    return validate(bytes, fileName: file.name);
  }

  /// Checks size and content. Throws an [AppException] when something is wrong.
  PickedImage validate(Uint8List bytes, {required String fileName}) {
    if (bytes.isEmpty) {
      throw const AppException('That file is empty. Please choose another photo.');
    }
    if (bytes.length > AppConstants.maxImageBytes) {
      throw const AppException(
        'That photo is too large. Please choose one under 5 MB.',
      );
    }
    final type = detectContentType(bytes);
    if (type == null) {
      throw const AppException(
        'That file is not a supported image. Please choose a JPG, PNG or WEBP photo.',
      );
    }
    return PickedImage(bytes: bytes, fileName: fileName, contentType: type);
  }

  /// Looks at the first bytes of the file (not the file name) to find out
  /// whether it is a JPEG, PNG or WEBP image. Returns null for anything else.
  static String? detectContentType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    // WEBP: "RIFF" + 4 size bytes + "WEBP"
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }
}
