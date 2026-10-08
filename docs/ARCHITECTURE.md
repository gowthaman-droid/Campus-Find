# Campus Find - Architecture

## 1. The big picture

```text
                 ┌─────────────────────────────┐
                 │  Flutter app (Android/Win)  │
                 └──────────────┬──────────────┘
        sign in / read / write  │            │  POST /match, /events ...
   ┌────────────────────────────┼──────┐     │  (Bearer = Firebase ID token)
   ▼                ▼           ▼      ▼     ▼
Firebase Auth   Firestore   Storage   FCM   Python FastAPI service
 (identity,     (source of  (item    (push)  (verifies the token, reads
  admin claim)    truth)    images)           Firestore, scores matches)
                    ▲                              │
                    └──── matches + notifications ─┘  (Admin SDK writes,
                                                       sends FCM push)
```

In plain words:

| Piece | What it does for Campus Find |
|---|---|
| **Flutter** | Draws every screen on Android and Windows. |
| **Firebase Authentication** | Handles register, login, logout, password reset. Carries the `admin` claim. |
| **Cloud Firestore** | Stores users, reports, claims, matches and notifications permanently. It is the single source of truth. |
| **Cloud Storage** | Stores item photos. |
| **Firebase Cloud Messaging (FCM)** | Delivers push notifications to Android phones. |
| **Python (FastAPI) service** | Calculates match scores, creates match records and notifications, sends pushes, and does admin jobs that need elevated rights. It never trusts the app's data: it re-reads reports from Firestore by ID. |

## 2. What replaced the original Python CLI

| CLI function | New home |
|---|---|
| `add_item()` | Report form in the app writes to Firestore, then calls `POST /match`. The API also offers `POST /reports`. |
| `search_item()` | Firestore keyword queries in the app; the API offers `GET /reports/search`. |
| `display_items()` | Live Firestore streams in the app; the API offers `GET /reports`. |
| `return_item()` | "Mark returned" in the app (checked by the security rules); the API offers `PATCH /reports/{id}/status`. |
| `items = []` | Firestore documents with permanent IDs. |
| `input()` / `print()` / `while True` | Gone. Screens replace the menu; JSON replaces `print`. |

## 3. Main data flows

**A. Register / login.** The app creates the Auth account, then writes `users/{uid}` with `role: student`. On every sign-in it forces a token refresh and reads the `admin` claim to decide whether to show admin screens.

**B. Report an item.**
1. The app uploads the optional photo to Storage and gets its download URL.
2. One batch writes `reports/{id}` and `reports/{id}/private/contact` (`matchStatus: pending`).
3. The app calls `POST /match {report_id}`.
4. The service loads that report, loads active reports of the opposite type, scores each pair, writes `matches/{lostId}_{foundId}` for good pairs, sets `matchStatus: done`, and notifies both owners when a match is strong.
5. If step 3 fails (service offline, timeout), the report is **not lost**: it is already saved, `matchStatus` becomes `failed`, and the user sees a "Retry matching" button. Admins can also run `POST /admin/rematch`.

**C. Match score (0-100).**

| Part | Weight | How it is measured |
|---|---|---|
| Item name | 35% | Fuzzy word overlap with a small synonym table (phone, mobile, iPhone are alike) |
| Location | 25% | Same campus area counts most; the detail text adds to it |
| Category | 15% | Same category = 100, otherwise 0 |
| Description | 15% | Fuzzy word overlap (this weight is redistributed if either description is empty) |
| Time | 10% | Half-life decay: the further apart lost and found times are, the lower the score (half-life 72 hours; a "found" earlier than the "lost" time scores 0) |

A pair is a match when score >= 55 and name similarity >= 30. Strong matches (>= 70) notify both users. A report is never matched with another report of the same person.

**D. Claim and return.**
1. On a found item a different user presses **Claim item**, writes `claims/{reportId}_{uid}` (message + verification details) and the app calls `POST /events {claim_submitted}`. The server notifies the finder.
2. The finder (or an admin) approves or rejects. Approval is one batch: claim `pending -> approved` and report `active -> claimed`. The rules refuse one without the other.
3. Once the claim is approved the claimant can read the finder's phone/e-mail (`private/contact`) and the finder can read the claimant's phone (on the claim).
4. After the hand-over the finder (or an admin) completes it: claim `approved -> completed` and report `claimed -> returned` (with `returnedAt`, `returnedTo`, `resolvedBy`). A returned report can never be returned again.

**E. Notifications.** Only the server creates `notifications/*` documents (so nobody can spam another user) and then sends the push. The app shows the live list from Firestore, which works on Windows too. FCM push exists on Android only.

**F. Admin.** Admin screens query Firestore directly (the rules let an admin read everything) and call the service for jobs the app must not do itself: change a user's role, disable an account, send a broadcast message.

## 4. Security in three layers

1. **UI**: admin screens are only shown when the token has `admin: true`. This is convenience, **not** protection.
2. **Firestore / Storage rules**: the real gatekeeper. They check who you are, what you may change, which fields, and which status moves are legal. Calling Firestore without the app gets you nowhere.
3. **Python service**: verifies the Firebase ID token on every request (except `/health`), checks the caller owns the report or is an admin, and validates input.

Other protections: contact details live in a separate document with its own rule; users cannot write match records, notifications, or counters; users cannot change their own role; image uploads are limited to your own folder, 5 MB, jpeg/png/webp.

## 5. Design decisions (and why)

* **State management: Provider + `ChangeNotifier`.** Smallest concept count for a beginner. Providers are created once in `main.dart`; screens use `context.watch<...>()` / `context.read<...>()`. Firestore streams are subscribed inside the providers and exposed as plain lists.
* **App writes reports directly to Firestore** (instead of through the API), so a report is never lost when the Python service is down.
* **Custom claim for admin** (not a Firestore field): the rules read it from the token without extra reads, and a user cannot edit it.
* **Claim ID = `reportId_claimantUid`**: prevents duplicate claims and gives the rules a direct path to a person's claim.
* **Soft moderation (`hidden`)** instead of deleting inappropriate reports: reversible and leaves an audit trail.
* **No Docker/Redis/Kubernetes**: not needed for a campus-scale app.

## 6. Platform notes and limits

* **Windows has no push** (FCM does not support Windows). Windows users still get the in-app notification list.
* **Cloud Storage requires the Blaze (pay-as-you-go) plan** on new Firebase projects. Small campus usage normally stays within the free allowance, but a billing account is required.
* **Deployed API must use `https://`.** Debug Android builds are allowed to call `http://10.0.2.2:8000`; release builds are not.
* **Search is keyword-based**: it finds words and word beginnings of item names, plus whole words elsewhere. It is not full-text search and handles English letters/digits only.
* **Firebase App Check** (protects against apps that are not yours) is a recommended future improvement.
