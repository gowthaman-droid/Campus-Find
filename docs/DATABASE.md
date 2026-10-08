# Campus Find - Database design

Persistent data lives in **Cloud Firestore** (documents) and **Cloud Storage for Firebase** (images).
The Python CLI's `items = []` list is gone: every record has a permanent document ID, never an array position.

**Conventions**

* **App** = the Flutter app. Its writes are checked by `firestore.rules`.
* **Server** = the Python service using the Firebase Admin SDK. It bypasses the rules, so it does its own checks.
* Timestamps are Firestore `timestamp` values. The app writes `FieldValue.serverTimestamp()`; the rules require the stored value to equal the server's `request.time`, so the phone's clock cannot be used to fake dates.
* "Required" means the key must exist. Optional text fields are stored as `''` (empty string) instead of being left out, so the rules can check exact key sets.

---

## 1. Collections at a glance

| Path | Document ID | Who creates it |
|---|---|---|
| `users/{uid}` | the Firebase Auth uid | App (at registration) |
| `users/{uid}/devices/{token}` | the FCM token | App (Android only) |
| `reports/{reportId}` | Firestore auto-ID | App (or Server via `POST /reports`) |
| `reports/{reportId}/private/contact` | always `contact` | App, in the same batch as the report |
| `claims/{reportId}_{claimantUid}` | report ID + `_` + claimant uid | App |
| `matches/{lostReportId}_{foundReportId}` | lost ID + `_` + found ID | Server only |
| `notifications/{notificationId}` | deterministic (see below) | Server only |
| `analytics/{docId}` | free | Server only (reserved) |

Relationships:

```text
users 1 ──── * reports            reports.userId = users.uid
reports 1 ── 1 private/contact    (phone + email of the reporter)
reports(found) 1 ── * claims      claims.reportId; claims.reportOwnerId = reports.userId
users 1 ──── * claims             claims.claimantId = users.uid
reports(lost) * ──── * reports(found)   through matches
users 1 ──── * notifications      notifications.userId
```

---

## 2. `users/{uid}`

| Field | Type | Req | Written by | Purpose |
|---|---|---|---|---|
| `uid` | string | yes | App (create) | Same as the document ID and the Auth uid |
| `name` | string, 2-80 | yes | App | Full name |
| `email` | string | yes | App (create) | Must equal the Auth e-mail (case-insensitive) |
| `phone` | string, 5-25 | yes | App | Contact phone |
| `role` | `student` / `admin` | yes | App creates `student`; Server changes it | **Display mirror only.** Security rules use the `admin` custom claim, never this field |
| `createdAt` | timestamp | yes | App | Sign-up time |
| `profileImage` | string (URL or `''`) | yes | App | Optional profile photo |
| `updatedAt` | timestamp | no | App | Set when the profile is edited |
| `disabled` | bool | no | Server | Mirror of the Auth "disabled" switch |

After sign-up an ordinary user can change only `name`, `phone`, `profileImage` (and `updatedAt`). They cannot touch `role`, `uid`, `email` or `createdAt`.

**Admin = custom claim.** `backend/scripts/make_admin.py` (or `POST /admin/users/{uid}/role`) sets `admin: true` on the user's Auth token and mirrors `role: 'admin'` here. The app decides whether to show admin screens from the token claim (`getIdTokenResult`), the same signal the rules use. A claim only reaches the user's token after sign-out/sign-in or a forced token refresh.

### `users/{uid}/devices/{token}`

| Field | Type | Req | Purpose |
|---|---|---|---|
| `token` | string | yes | FCM registration token (also the document ID) |
| `platform` | string | yes | `android` (Windows has no FCM) |
| `createdAt` | timestamp | no | First registered |
| `updatedAt` | timestamp | yes | Last refreshed |

Only the owner can read or write these. The Server reads them to send pushes.

---

## 3. `reports/{reportId}`

The public part of a lost or found report. **Phone and e-mail are NOT stored here** (see `private/contact`).

| Field | Type | Req | Written by | Purpose |
|---|---|---|---|---|
| `id` | string | yes | App | Equals the document ID |
| `type` | `lost` / `found` | yes | App | Never changes |
| `userId` | string | yes | App | Owner's uid. Never changes. Must equal the signed-in user at creation |
| `reporterName` | string, 1-80 | yes | App | Display name shown on the item page |
| `itemName` | string, 2-100 | yes | App | e.g. "Black leather wallet" |
| `category` | string, 2-40 | yes | App | One of the categories in section 9 |
| `description` | string, 1-1000 | yes | App | Colour, brand, marks... |
| `additionalDetails` | string, 0-1000 | yes | App | `''` if none |
| `location` | string, 2-80 | yes | App | Campus area (list in section 9) |
| `locationDetail` | string, 0-120 | yes | App | Exact spot, `''` if none |
| `eventAt` | timestamp | yes | App | When it was lost/found (form "date" + "time" combined) |
| `imageUrl` | string, 0-2048 | yes | App | Download URL, `''` if no photo |
| `imagePath` | string, 0-300 | yes | App | Storage path `report_images/{uid}/...`, `''` if no photo |
| `status` | `active` / `claimed` / `returned` | yes | App | Lifecycle (section 6) |
| `hidden` | bool | yes | App (admin only after creation) | Moderation switch. Hidden reports are readable only by the owner and admins |
| `matchStatus` | `pending` / `done` / `failed` | yes | App sets `pending`/`failed`; Server sets `done` | State of the matching run |
| `keywords` | list of string, max 80 | yes | App | Search tokens (section 7) |
| `createdAt` | timestamp | yes | App | |
| `updatedAt` | timestamp | yes | App | Every write sets it |
| `matchCount` | int | no | **Server only** | Number of active matches |
| `bestMatchScore` | int 0-100 | no | **Server only** | Highest match score (shown as "Match score" on the item page) |
| `lastMatchedAt` | timestamp | no | **Server only** | Last matching run |
| `hiddenReason` | string, 0-300 | no | App (admin) | Why a report was hidden |
| `hiddenBy` | string | no | App (admin) | Admin's uid |
| `returnedAt` | timestamp | no | App | Set when `status` becomes `returned` |
| `returnedTo` | string, 1-100 | no | App | Name of the person who got the item back |
| `resolvedBy` | string | no | App | uid of the person who marked it returned |

A new report must contain exactly the 19 keys marked "yes" above (no extras). Apps that read a document treat the "no" fields as optional with defaults (`matchCount = 0`, etc.).

### `reports/{reportId}/private/contact`

| Field | Type | Req | Purpose |
|---|---|---|---|
| `userId` | string | yes | Owner's uid |
| `phone` | string, 5-25 | yes | Reporter's phone |
| `email` | string, 3-254 | yes | Reporter's e-mail |
| `updatedAt` | timestamp | yes | |

Readable only by the report's owner, an admin, or a person whose claim on this report is `approved` or `completed`. This is how contact details are revealed only to authorised people.

---

## 4. `claims/{reportId}_{claimantUid}`

A claim is always made on a **found** report. The ID format guarantees one claim per person per item, and lets the rules find a person's claim directly.

| Field | Type | Req | Written by | Purpose |
|---|---|---|---|---|
| `claimId` | string | yes | App | Equals the document ID |
| `reportId` | string | yes | App | The found report |
| `reportOwnerId` | string | yes | App | Must equal the report's `userId` (rules verify it) |
| `claimantId` | string | yes | App | Must equal the signed-in user |
| `claimantName` | string, 1-80 | yes | App | Shown to the reviewer |
| `claimantPhone` | string, 0-25 | yes | App | Shown to the reviewer so they can arrange the hand-over |
| `reportItemName` | string | yes | App | Copy of the item name for list screens (rules verify it) |
| `message` | string, 10-1000 | yes | App | Why this item is theirs |
| `verificationDetails` | string, 5-1000 | yes | App | Proof only the owner would know (marks, contents, serial number) |
| `status` | `pending` / `approved` / `rejected` / `completed` | yes | App | Starts as `pending` |
| `createdAt` | timestamp | yes | App | |
| `reviewedAt` | timestamp | no | App (reviewer) | Time of the latest review action |
| `reviewedBy` | string | no | App (reviewer) | Reviewer's uid |
| `reviewNote` | string, 0-500 | no | App (reviewer) | Optional reason |
| `completedAt` | timestamp | no | App (reviewer) | Set when `completed` |

Who can read: the claimant, the owner of the found report, admins.
Who can review (change `status`): the owner of the found report, or an admin. The claimant can only withdraw (delete) a still-`pending` claim.
A claim that was rejected cannot be re-submitted by the same person (the document already exists); they should contact an admin.

---

## 5. `matches`, `notifications`, `analytics` (server-written)

### `matches/{lostReportId}_{foundReportId}`

| Field | Type | Purpose |
|---|---|---|
| `id` | string | Same as the document ID |
| `lostReportId`, `foundReportId` | string | The pair |
| `lostUserId`, `foundUserId` | string | Owners of the two reports |
| `participants` | list of 2 strings | `[lostUserId, foundUserId]`; lets one query `participants array-contains uid` find a user's matches |
| `lostItemName`, `foundItemName` | string | Copies for list screens |
| `score` | int 0-100 | Overall match score |
| `strong` | bool | `score >= 70` (both people are notified) |
| `breakdown` | map | `{name, location, category, description, time}`, each 0-100 |
| `status` | `active` / `resolved` | `resolved` once either report is returned |
| `createdAt`, `updatedAt` | timestamp | |

Readable by the two participants and admins. The app can never create or change a match; only an admin can delete one.

### `notifications/{notificationId}`

| Field | Type | Purpose |
|---|---|---|
| `userId` | string | Recipient |
| `type` | string | `match_found`, `claim_submitted`, `claim_approved`, `claim_rejected`, `item_returned`, `admin_message` |
| `title`, `body` | string | Text shown in the app and in the push |
| `reportId`, `claimId`, `matchId` | string, optional | Used to open the right screen when tapped |
| `read` | bool | The only field the recipient may change |
| `createdAt` | timestamp | |

IDs are deterministic (for example `claim_approved_{claimId}`, `match_{matchId}_{userId}`), so retrying an event can never create a duplicate.

### `analytics/{docId}`

Reserved for server-written summary snapshots; admin read only. The analytics screen itself calculates live numbers from the real collections with Firestore `count()` queries (with a fallback for platforms that lack `count()`), so nothing in it is hard-coded.

---

## 6. Lifecycles and the "one batch" rule

**Report `status`:** `active` -> `claimed` -> `returned`, or `active` -> `returned` directly, or `claimed` -> `active` (claim revoked). `returned` is final for everyone; admins can still hide a returned report.

**Claim `status`:** `pending` -> `approved` | `rejected`; `approved` -> `completed` | `rejected`.

The rules force claim and report to move together. Each action below is ONE atomic batch (all writes succeed or none):

| Action | Done by | Writes in the batch |
|---|---|---|
| Create report | owner | `reports/{id}` + `reports/{id}/private/contact`; then call `POST /match` |
| Submit claim | claimant | `claims/{reportId}_{uid}` (the found report must be `active`, visible and not yours); then `POST /events` |
| Approve claim | report owner or admin | claim `pending -> approved` + report `active -> claimed` (+ other pending claims `-> rejected`) |
| Reject claim | report owner or admin | claim `pending -> rejected` (or `approved -> rejected` plus report `claimed -> active`) |
| Complete hand-over | report owner or admin | claim `approved -> completed` + report `claimed -> returned` with `returnedAt`, `returnedTo`, `resolvedBy` |
| Return without a claim | owner or admin | report `-> returned` with the same three fields |
| Hide / unhide | admin | report `hidden`, `hiddenBy`, `hiddenReason` |

Trying to "return" an already returned report is refused by the rules, by the app's transaction and by `PATCH /reports/{id}/status` (HTTP 409).

---

## 7. Search design (Firestore has no "contains" search)

Every report stores `keywords`, built identically by `lib/utils/search_keywords.dart` and `backend/services/search_keywords.py`:

1. Lower-case everything; split into words with the pattern `[a-z0-9]+` (English letters and digits only; text in other scripts yields no keywords but still shows in the normal list).
2. Drop one-letter words and these stop-words: `the and for with near from this that was are has have lost found`.
3. From `itemName`: store every word, and also every prefix of length 3 up to the full word (so "wal" finds "wallet").
4. From `category`, `location`, `locationDetail`, and the first 30 words of `description`: store whole words.
5. Remove duplicates; keep at most 80.

A search turns the typed text into words the same way (at most 10 words) and runs `keywords array-contains-any [...]`, combined with equality filters on `hidden`, `type`, `status`, `category`, `location`, ordered by `createdAt` newest first. Results are then ranked in the app by how many words matched. Firestore allows at most 30 values in `array-contains-any` and one such clause per query.

**Shared test vector** (used by both the Dart tests and the Python tests, so the two implementations can never drift apart):

```text
itemName       Black Leather Wallet
category       Wallets & Purses
location       Library
locationDetail 2nd floor
description    Brown stitching with college ID card
keywords ->    black, leather, wallet, wallets, purses, library, 2nd, floor, brown,
               stitching, college, id, card, bla, blac, lea, leat, leath, leathe,
               wal, wall, walle
```

Every browse/search query **must** include `hidden == false` (the rules need it, see the note at the top of `firestore.rules`).

---

## 8. Indexes (`firestore.indexes.json`)

Equality filters plus `orderBy createdAt desc` need composite indexes. We create one small index per filter field, always ending in `createdAt DESC`, and Firestore **merges** them to answer any combination:

| Collection | Index (field, then createdAt DESC) | Used by |
|---|---|---|
| reports | `hidden` | all browse/search/admin queries |
| reports | `type`, `status`, `category`, `location` | optional search filters |
| reports | `userId` | My Reports |
| reports | `matchStatus` | retry of pending/failed matching |
| reports | `keywords` (array-contains) | keyword search |
| claims | `claimantId` | My Claims |
| claims | `reportOwnerId` | claims waiting for my review |
| claims | `reportId` | claims on one item |
| claims | `status` | admin: pending claims |
| matches | `participants` (array-contains) | My matches |
| matches | `status` | admin: active matches |
| notifications | `userId` | My notifications |

Single-field filters, plain `orderBy createdAt` and `count()` queries with only equality filters need no composite index (Firestore creates single-field indexes automatically). If Flutter ever prints "The query requires an index" with a link, open the link (or add the index to the file) and run `firebase deploy --only firestore:indexes`; indexes take a few minutes to build.

---

## 9. Fixed lists (defaults, editable in `lib/utils/constants.dart`)

* **Categories:** Electronics; ID Cards & Documents; Wallets & Purses; Keys; Bags & Backpacks; Clothing; Books & Stationery; Accessories & Jewellery; Sports Gear; Other.
* **Campus areas (`location`):** Library; Canteen; Academic Block; Hostel; Sports Ground; Auditorium; Parking Area; Main Gate; Bus Stop; Other.
* **Matching thresholds:** a pair is a match when score >= 55 and name similarity >= 30; both people are notified when score >= 70.

Because `location` comes from a fixed list, the analytics screen can count reports per area and per category with plain `count()` queries.

## 10. Storage paths (`storage.rules`)

* `report_images/{uid}/{reportId}/{fileName}` - item photo (jpeg/png/webp, under 5 MB, only the owner uploads).
* `profile_images/{uid}/{fileName}` - optional profile photo.
