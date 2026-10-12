import 'dart:typed_data';

/// A photo the person chose, already checked (real image, under 5 MB).
/// Created by ImageService; uploaded by StorageService.
class PickedImage {
  const PickedImage({
    required this.bytes,
    required this.fileName,
    required this.contentType,
  });

  final Uint8List bytes;

  /// The name the file had on the device (only used for display).
  final String fileName;

  /// `image/jpeg`, `image/png` or `image/webp`.
  final String contentType;

  int get sizeInBytes => bytes.length;

  /// File extension that goes with [contentType].
  String get extension {
    switch (contentType) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      default:
        return 'jpg';
    }
  }

  /// "340 KB" or "1.2 MB"
  String get sizeLabel {
    const megabyte = 1024 * 1024;
    if (bytes.length >= megabyte) {
      return '${(bytes.length / megabyte).toStringAsFixed(1)} MB';
    }
    return '${(bytes.length / 1024).round()} KB';
  }
}
