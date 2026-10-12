import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/claim_service.dart';
import '../services/image_service.dart';
import '../services/match_service.dart';
import '../services/notification_service.dart';
import '../services/report_service.dart';
import '../services/storage_service.dart';
import '../services/user_service.dart';
import 'admin_provider.dart';
import 'analytics_provider.dart';
import 'auth_provider.dart';
import 'claim_provider.dart';
import 'dashboard_provider.dart';
import 'match_provider.dart';
import 'notification_provider.dart';
import 'report_provider.dart';
import 'search_provider.dart';

/// The ONE place where every service and provider of the app is created.
/// main.dart wraps the whole app in it:
///
/// ```dart
/// runApp(const AppProviders(child: CampusFindApp()));
/// ```
///
/// There are two layers:
///
///  1. SERVICES (`Provider`): plain objects that talk to Firebase or to the
///     Python service. They hold no screen state and never change, so they
///     are created once and read with `context.read<...>()`.
///
///  2. STATE (`ChangeNotifierProvider` / `ChangeNotifierProxyProvider`): the
///     objects screens watch. [AuthProvider] knows who is signed in. Every
///     other provider is a PROXY of it: whenever the signed-in person changes,
///     Flutter calls its `update`, and the provider starts (or stops) its live
///     Firestore listeners for that person. That is why logging out
///     automatically empties every list in the app.
///
/// Providers are created with `lazy: false` where they must already be
/// listening when the person logs in (reports, claims, matches, notifications).
class AppProviders extends StatelessWidget {
  const AppProviders({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // ------------------------------------------------------------
        // 1. Services
        // ------------------------------------------------------------
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<UserService>(create: (_) => UserService()),
        Provider<StorageService>(create: (_) => StorageService()),
        Provider<ImageService>(create: (_) => ImageService()),
        Provider<BackendApiService>(
          create: (context) => BackendApiService(
            tokenProvider: context.read<AuthService>().getIdToken,
          ),
          dispose: (_, api) => api.close(),
        ),
        Provider<ReportService>(
          create: (context) => ReportService(
            storage: context.read<StorageService>(),
            api: context.read<BackendApiService>(),
          ),
        ),
        Provider<ClaimService>(
          create: (context) => ClaimService(
            api: context.read<BackendApiService>(),
          ),
        ),
        Provider<MatchService>(
          create: (context) => MatchService(
            api: context.read<BackendApiService>(),
          ),
        ),
        Provider<NotificationService>(create: (_) => NotificationService()),
        Provider<AnalyticsService>(create: (_) => AnalyticsService()),

        // ------------------------------------------------------------
        // 2. State
        // ------------------------------------------------------------
        ChangeNotifierProvider<AuthProvider>(
          lazy: false,
          create: (context) => AuthProvider(
            auth: context.read<AuthService>(),
            users: context.read<UserService>(),
            storage: context.read<StorageService>(),
          ),
        ),
        ChangeNotifierProxyProvider<AuthProvider, ReportProvider>(
          lazy: false,
          create: _newReportProvider,
          update: (context, auth, previous) {
            final provider = previous ?? _newReportProvider(context);
            provider.bindUser(auth.profile);
            return provider;
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, ClaimProvider>(
          lazy: false,
          create: _newClaimProvider,
          update: (context, auth, previous) {
            final provider = previous ?? _newClaimProvider(context);
            provider.bindUser(auth.profile);
            return provider;
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, MatchProvider>(
          lazy: false,
          create: _newMatchProvider,
          update: (context, auth, previous) {
            final provider = previous ?? _newMatchProvider(context);
            provider.bindUser(auth.uid);
            return provider;
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, NotificationProvider>(
          lazy: false,
          create: _newNotificationProvider,
          update: (context, auth, previous) {
            final provider = previous ?? _newNotificationProvider(context);
            provider.bindUser(auth.uid);
            return provider;
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, SearchProvider>(
          create: _newSearchProvider,
          update: (context, auth, previous) {
            final provider = previous ?? _newSearchProvider(context);
            provider.bindUser(auth.uid);
            return provider;
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, DashboardProvider>(
          create: _newDashboardProvider,
          update: (context, auth, previous) {
            final provider = previous ?? _newDashboardProvider(context);
            provider.bindUser(auth.uid);
            return provider;
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, AnalyticsProvider>(
          create: _newAnalyticsProvider,
          update: (context, auth, previous) {
            final provider = previous ?? _newAnalyticsProvider(context);
            provider.bindUser(auth.isAdmin ? auth.uid : null);
            return provider;
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, AdminProvider>(
          create: _newAdminProvider,
          update: (context, auth, previous) {
            final provider = previous ?? _newAdminProvider(context);
            provider.bindAdmin(uid: auth.uid, isAdmin: auth.isAdmin);
            return provider;
          },
        ),
      ],
      child: child,
    );
  }

  static ReportProvider _newReportProvider(BuildContext context) {
    return ReportProvider(
      reports: context.read<ReportService>(),
      matches: context.read<MatchService>(),
    );
  }

  static ClaimProvider _newClaimProvider(BuildContext context) {
    return ClaimProvider(claims: context.read<ClaimService>());
  }

  static MatchProvider _newMatchProvider(BuildContext context) {
    return MatchProvider(matches: context.read<MatchService>());
  }

  static NotificationProvider _newNotificationProvider(BuildContext context) {
    return NotificationProvider(
      notifications: context.read<NotificationService>(),
    );
  }

  static SearchProvider _newSearchProvider(BuildContext context) {
    return SearchProvider(reports: context.read<ReportService>());
  }

  static DashboardProvider _newDashboardProvider(BuildContext context) {
    return DashboardProvider(
      reports: context.read<ReportService>(),
      matches: context.read<MatchService>(),
    );
  }

  static AnalyticsProvider _newAnalyticsProvider(BuildContext context) {
    return AnalyticsProvider(analytics: context.read<AnalyticsService>());
  }

  static AdminProvider _newAdminProvider(BuildContext context) {
    return AdminProvider(
      analytics: context.read<AnalyticsService>(),
      users: context.read<UserService>(),
      reports: context.read<ReportService>(),
      claims: context.read<ClaimService>(),
      matches: context.read<MatchService>(),
      notifications: context.read<NotificationService>(),
      api: context.read<BackendApiService>(),
    );
  }
}
