import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_find/models/picked_image.dart';
import 'package:campus_find/services/auth_service.dart';
import 'package:campus_find/services/image_service.dart';
import 'package:campus_find/utils/app_exception.dart';
import 'package:campus_find/utils/constants.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytesOf(List<int> values) => Uint8List.fromList(values);

String fakeToken(Map<String, dynamic> payload) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode(<String, dynamic>{'alg': 'none'})}.${encode(payload)}.signature';
}

void main() {
  final jpeg = bytesOf(<int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
  final png = bytesOf(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0]);
  final webp = bytesOf(<int>[
    0x52, 0x49, 0x46, 0x46, // RIFF
    0x01, 0x02, 0x03, 0x04, // size
    0x57, 0x45, 0x42, 0x50, // WEBP
  ]);

  group('ImageService.detectContentType', () {
    test('recognises JPEG, PNG and WEBP by their first bytes', () {
      expect(ImageService.detectContentType(jpeg), 'image/jpeg');
      expect(ImageService.detectContentType(png), 'image/png');
      expect(ImageService.detectContentType(webp), 'image/webp');
    });

    test('rejects everything else, whatever the file name says', () {
      expect(ImageService.detectContentType(bytesOf(utf8.encode('hello world'))), isNull);
      expect(ImageService.detectContentType(bytesOf(<int>[0xFF, 0xD8])), isNull);
      expect(ImageService.detectContentType(Uint8List(0)), isNull);
    });
  });

  group('ImageService.validate', () {
    final service = ImageService();

    test('accepts a real image', () {
      final image = service.validate(jpeg, fileName: 'photo.jpg');
      expect(image.contentType, 'image/jpeg');
      expect(image.extension, 'jpg');
      expect(image.fileName, 'photo.jpg');
    });

    test('rejects an empty file', () {
      expect(
        () => service.validate(Uint8List(0), fileName: 'a.jpg'),
        throwsA(isA<AppException>()),
      );
    });

    test('rejects a file over 5 MB', () {
      final tooBig = Uint8List(AppConstants.maxImageBytes + 1);
      expect(
        () => service.validate(tooBig, fileName: 'big.jpg'),
        throwsA(
          isA<AppException>().having((e) => e.message, 'message', contains('too large')),
        ),
      );
    });

    test('rejects a file that is not an image', () {
      expect(
        () => service.validate(bytesOf(utf8.encode('not an image')), fileName: 'x.jpg'),
        throwsA(
          isA<AppException>().having((e) => e.message, 'message', contains('not a supported image')),
        ),
      );
    });
  });

  group('PickedImage', () {
    test('extension and size label', () {
      final small = PickedImage(
        bytes: Uint8List(348160),
        fileName: 'a.png',
        contentType: 'image/png',
      );
      expect(small.extension, 'png');
      expect(small.sizeLabel, '340 KB');

      final big = PickedImage(
        bytes: Uint8List(1572864),
        fileName: 'b.webp',
        contentType: 'image/webp',
      );
      expect(big.extension, 'webp');
      expect(big.sizeLabel, '1.5 MB');
    });
  });

  group('AuthService.claimsFromToken', () {
    test('reads the admin claim', () {
      final claims = AuthService.claimsFromToken(
        fakeToken(<String, dynamic>{'admin': true, 'email': 'a@b.edu'}),
      );
      expect(claims['admin'], isTrue);
      expect(claims['email'], 'a@b.edu');
    });

    test('a normal user has no admin claim', () {
      final claims =
          AuthService.claimsFromToken(fakeToken(<String, dynamic>{'email': 'a@b.edu'}));
      expect(claims['admin'], isNull);
    });

    test('garbage gives an empty map instead of an error', () {
      expect(AuthService.claimsFromToken('not-a-token'), isEmpty);
      expect(AuthService.claimsFromToken('a.%%%.c'), isEmpty);
      expect(AuthService.claimsFromToken(''), isEmpty);
    });
  });
}
