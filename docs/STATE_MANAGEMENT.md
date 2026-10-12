# Campus Find - State management (Provider)

"State" is everything the screens show that can change: who is logged in, the list of my reports, the search results, the number on the notification bell. This document explains how the app keeps it, in plain words.

## 1. Why Provider

* It is the simplest approach that still works well with Firebase, and it is one of the approaches recommended in the Flutter documentation.
* There are only three ideas to learn: a `ChangeNotifier` (a class that holds data and says "I changed"), `Provider` (puts it where screens can find it), and `context.watch` / `context.read` (how a screen uses it).
* No code generation, no special syntax. Riverpod and Bloc are more powerful, but they ask a beginner to learn much more before the first screen works.

## 2. Two layers

```text
 Screens (Phase 10-20)
    │  watch / read
    ▼
 PROVIDERS  (lib/providers)      hold the data screens show, run actions,
    │                            turn every error into a friendly sentence
    ▼
 SERVICES   (lib/services)       talk to Firebase and to the Python service;
    │                            know nothing about screens
    ▼
 Firebase Auth / Firestore / Storage / Python API
```

Rule: **screens talk to providers, providers talk to services, only services talk to Firebase.** (The one exception: a screen may use `ImageService` to open the photo picker, because that is a UI helper that touches no data.)

## 3. Where everything is created

`lib/providers/app_providers.dart` is the only place where services and providers are created. `main.dart` (Phase 10) wraps the whole app in it:

```dart
runApp(const AppProviders(child: CampusFindApp()));
```

* Services are plain `Provider`s: created once, never change, read with `context.read<ReportService>()`.
* `AuthProvider` knows who is signed in.
* Every other provider is a **proxy of `AuthProvider`**: when the signed-in person changes (log in, log out, switch account), Flutter calls the proxy's `update`, which calls `bindUser(...)`. The provider then starts or stops its live Firestore listeners. That is why logging out empties every list in the app, and why one person can never see another person's cached data.

## 4. The providers

| Provider | Holds | Live? | Bound to |
|---|---|---|---|
| `AuthProvider` | login state (`AuthStatus`), profile, admin flag; register, login, logout, reset password, edit profile | yes (Firebase) | - |
| `ReportProvider` | my reports; submit, edit, delete, mark returned, retry matching; upload progress | yes | profile |
| `SearchProvider` | filters, results, paging, empty/error state | one-shot pages | uid |
| `ClaimProvider` | claims I made, claims on my found items; submit, approve, reject, complete, withdraw | yes | profile |
| `MatchProvider` | my active matches, best score per report | yes | uid |
| `NotificationProvider` | notification list, unread badge; mark read, delete | yes | uid |
| `DashboardProvider` | the four numbers on the home screen | one-shot counts | uid |
| `AnalyticsProvider` | numbers and charts data (admin) | one-shot counts | uid, admin only |
| `AdminProvider` | admin dashboard numbers, live lists of everything, admin actions | stats one-shot, lists via streams | uid + admin flag |

## 5. How a screen uses state

```dart
// Show data: watch in build(). The screen rebuilds when the data changes.
final reports = context.watch<ReportProvider>().myReports;

// Only part of a provider? Selector rebuilds just for that part.
final unread = context.select<NotificationProvider, int>((n) => n.unreadCount);

// Do something (button press): read in the callback, never watch there.
final result = await context.read<ClaimProvider>().submitClaim(
      report: report,
      message: message,
      verificationDetails: proof,
    );
if (!mounted) return;
showMessage(result.message, isError: !result.success, isWarning: result.isWarning);
```

* **Actions return `ActionResult`** (`success`, `message`, `isWarning`, `data`). They never throw. `message` is already a friendly sentence, so a screen only decides the colour.
* **Lists, loading and error are plain properties** (`items`, `loading`, `error`). A screen shows a spinner while `loading`, an error box when `error != null`, and an empty state when the list is empty.
* **One item at a time** (the details screen) uses a stream from the provider with `StreamBuilder`, for example `ReportProvider.watchReport(id)` or `ClaimProvider.claimsForReport(report)`.
* **Screens that load on demand** call `ensureLoaded()` / `refresh()` / `load()` when they open (`SearchProvider`, `DashboardProvider`, `AnalyticsProvider`, `AdminProvider.loadStats`).
* **Buttons** are disabled while `busy` / `saving` is true, which stops double submissions.

## 6. How Firebase state is handled

1. **Live data**: a service returns a `Stream` (Firestore `snapshots()`). The provider listens once, copies each answer into a list and calls `notifyListeners()`. Every screen that watches the provider updates by itself, for example when a match is found or a claim is approved.
2. **Listeners follow the person**: `bindUser(...)` cancels old listeners and starts new ones. Providers never keep listening after logout.
3. **Errors**: every `catch` ends in `friendlyError(error)` (lib/utils/app_exception.dart). Raw Firebase or server text is never shown.
4. **Offline**: Firestore keeps writes made offline and sends them later. Reports show a "waiting to sync" flag (`Report.pendingSync`); matching is retried automatically (`MatchService.retryPending`). Claim actions need a connection on purpose (they are transactions).
5. **Races**: `SearchProvider`, `DashboardProvider`, `AnalyticsProvider` and `AdminProvider` number every request and ignore an answer that belongs to an older one, so a slow reply can never overwrite a newer result.
6. **Safe notifications**: `SafeNotifier` stops a late answer from notifying a provider that was disposed, and `notifyListenersSoon()` is used when state changes while Flutter is building widgets (inside a ProxyProvider `update`).
7. **Admin**: the admin flag comes from the sign-in token's `admin` claim. `AdminProvider` refuses to act for non-admins, but that is only a convenience. The real protection is in `firestore.rules` and the Python service (see docs/ARCHITECTURE.md, "Security in three layers").

## 7. Rules of thumb for screen authors

* `context.watch` / `context.select` inside `build()`; `context.read` inside callbacks (`onPressed`, `initState`).
* After an `await`, check `if (!mounted) return;` before using `context`.
* Never call a Firebase class from a screen. If a screen needs data that no provider offers, add a method to the provider (and, if needed, to the service).
* Show `result.message` as it is. Do not build your own error text from exceptions.
