import 'package:flutter/foundation.dart';

/// Fixed values used across the app. None of these are secrets.
class AppConstants {
  AppConstants._();

  static const String appName = 'Campus Find';
  static const String appVersion = '1.0.0';

  /// Item categories. Stored exactly as written in `reports.category`.
  static const List<String> categories = <String>[
    'Electronics',
    'ID Cards & Documents',
    'Wallets & Purses',
    'Keys',
    'Bags & Backpacks',
    'Clothing',
    'Books & Stationery',
    'Accessories & Jewellery',
    'Sports Gear',
    'Other',
  ];

  /// Campus areas. Stored exactly as written in `reports.location`.
  /// Change this list to match your own campus.
  static const List<String> locations = <String>[
    'Library',
    'Canteen',
    'Academic Block',
    'Hostel',
    'Sports Ground',
    'Auditorium',
    'Parking Area',
    'Main Gate',
    'Bus Stop',
    'Other',
  ];

  // ---- Field limits. They mirror firestore.rules: change both together. ----
  static const int personNameMin = 2;
  static const int personNameMax = 80;
  static const int phoneMin = 5;
  static const int phoneMax = 25;
  static const int itemNameMin = 2;
  static const int itemNameMax = 100;
  static const int descriptionMinUi = 10; // the form asks for a useful text
  static const int descriptionMax = 1000;
  static const int additionalDetailsMax = 1000;
  static const int locationDetailMax = 120;
  static const int claimMessageMin = 10;
  static const int claimMessageMax = 1000;
  static const int verificationMin = 5;
  static const int verificationMax = 1000;
  static const int reviewNoteMax = 500;
  static const int hiddenReasonMax = 300;
  static const int returnedToMax = 100;
  static const int passwordMin = 8;

  // ---- Matching thresholds. They mirror backend/config.py. ----
  static const int matchThreshold = 55;
  static const int strongMatchThreshold = 70;

  // ---- Images ----
  static const int maxImageBytes = 5 * 1024 * 1024;
  static const List<String> allowedImageExtensions = <String>[
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  // ---- Networking and paging ----
  static const Duration apiTimeout = Duration(seconds: 15);
  static const int pageSize = 20;
}

/// Firestore collection and document names, in one place so a typo can only
/// happen once.
class FirestorePaths {
  FirestorePaths._();

  static const String users = 'users';
  static const String devices = 'devices';
  static const String reports = 'reports';
  static const String reportPrivate = 'private';
  static const String contactDoc = 'contact';
  static const String claims = 'claims';
  static const String matches = 'matches';
  static const String notifications = 'notifications';
  static const String analytics = 'analytics';

  /// One claim per person per item: `{reportId}_{claimantUid}`.
  static String claimId(String reportId, String claimantUid) =>
      '${reportId}_$claimantUid';

  /// Match records are created by the Python service: `{lostId}_{foundId}`.
  static String matchId(String lostReportId, String foundReportId) =>
      '${lostReportId}_$foundReportId';
}

/// Cloud Storage folders. They must match storage.rules.
class StoragePaths {
  StoragePaths._();

  static String reportImage(String uid, String reportId, String fileName) =>
      'report_images/$uid/$reportId/$fileName';

  static String profileImage(String uid, String fileName) =>
      'profile_images/$uid/$fileName';
}

/// Settings that depend on where the app runs.
class AppConfig {
  AppConfig._();

  /// Optional override given at build/run time:
  ///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
  ///   flutter run --dart-define-from-file=config/dev.json
  static const String _apiBaseUrlFromBuild =
      String.fromEnvironment('API_BASE_URL');

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// FCM push notifications are used on Android only in this project
  /// (Windows has no FCM support).
  static bool get supportsPush => isAndroid;

  /// Where the Python matching service lives.
  /// - Android emulator: the host PC is reachable as 10.0.2.2
  /// - Windows desktop: 127.0.0.1 (not "localhost", which may resolve to IPv6)
  static String get apiBaseUrl {
    if (_apiBaseUrlFromBuild.isNotEmpty) {
      return _apiBaseUrlFromBuild;
    }
    if (isAndroid) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }
}
