# Storage: on the phone, backed up and shared through the family's own iCloud

Decided 2026-10-20. Replaces the server backup (Vercel Blob + Supabase) built earlier the same day.

## The rule

Footage and voice notes live on the phone. Yearfilm runs no server that ever holds them.
If someone turns on backup, or makes the film with family, the files go to **their own
iCloud** through CloudKit, under their Apple ID and their iCloud storage. Yearfilm's servers
hold only the waitlist.

## What the app does

**Library (unchanged).** SwiftData rows plus files in `Application Support/Media`. This stays
the source of truth; the app works with iCloud off, signed out, or full.

**Backup — opt-in, Settings → "Back up to iCloud".** One custom record zone per film year,
`Film-2026`, in the CloudKit **private** database of `iCloud.com.yearfilm.app`. One record per clip and per voice
note: its id, filmed day, length, film year and week, who added it, and the file as a
`CKAsset`. `CKSyncEngine` (iOS 17) does the batching, retries, account changes and push
notifications. On a new phone with the same Apple ID, turning backup on restores the library:
records are fetched, assets downloaded into `Media/`, rows inserted (deduplicated by id).

**Family — "Invite family" shares that year's zone.** A zone-wide `CKShare` with read-write
permission, sent with the system share sheet (Messages, Mail…), so an invite covers one
year's film and nothing else. A `FilmInfo` record in the zone carries the family name, the
year and, optionally, the weeks the producer is asking for. Relatives tap the link and accept
(through the window scene delegate); their app then **sends** their own clips from those
weeks into the shared zone with plain record saves, and **downloads nothing**: relatives'
phones never fill up with the whole family's footage. The producer's private-database engine
sees the new records and pulls the clips into the library, marked with who added them.

Why not SwiftData's built-in CloudKit sync: it only syncs the private database (no sharing),
it can't keep `@Attribute(.unique)`, and it would hold whole video files in memory as
`Data`. A small explicit sync layer over `CKSyncEngine` keeps files as files.

## Trade-offs to know

- **Everything counts against the producer's iCloud storage**, contributors' clips included,
  because a shared zone belongs to its owner. A full iCloud stops sync (`quotaExceeded`); the
  app says so and keeps everything on the phone.
- **Week-limited invites become a suggestion.** A CloudKit share can't restrict which records
  a participant writes, so "send us your Thanksgiving clips" filters in the contributor's app,
  not on a server.
- **The final film is made on the phone.** With no footage on a server, the engine's render
  (`engine/`) can't run there. The rough cut already cuts on the phone; the real film follows
  the same path, or asks the producer to send footage to a render explicitly, later.
- **Asset size.** An Apple engineer says a `CKAsset` can be up to 50 GB within the user's
  quota ([forum](https://developer.apple.com/forums/thread/827897)); older docs say 50 MB for
  CloudKit Web Services only. Verify with a real long 4K clip on a signed build.
- **Nothing CloudKit runs in an unsigned simulator build.** It needs `DEVELOPMENT_TEAM`, the
  container `iCloud.com.yearfilm.app` created in the developer account, and a signed build
  on a device or a simulator signed into iCloud.

## Privacy

Data in the user's own iCloud (private database, and shares they create) isn't collected by
the developer, so the App Store label goes back to **Data Not Collected** and
`PrivacyInfo.xcprivacy` declares no collected types. The privacy page says where things go:
the phone, and the user's iCloud if they turn it on; family members they invite can see the
shared film.

## What goes

- Web: `/api/uploads*`, `/api/account`, `/api/family*`, `/api/profile`, `/api/invites*`,
  `/join/[token]`, `lib/server.ts`, `lib/media.ts`, `lib/invites.ts`, `lib/invite-lookup.ts`,
  `lib/weeks.ts`, `scripts/e2e-backup.sh`, and the `@vercel/blob`, `@supabase/supabase-js`
  and `server-only` packages. The waitlist route stays as it is.
- Supabase: a migration drops `family_invites`, `profiles`, `voice_notes`, `footage`,
  `family_members`, `families` and `my_family_ids()` (all empty). `waitlist` stays.
- iOS: Supabase Auth and Sign in with Apple, the background uploader, the yearfilm.com API
  client, the server account screens. iCloud is the identity now; there is no Yearfilm account.
- Left in place for the owner to remove: the `yearfilm-blob` store (checked empty: 0 files)
  and its `BLOB_*` environment variables on Vercel, and the Supabase Auth settings and the one
  test user.

## How it's kept safe

- **CloudKit never starts at launch.** The container and engine are created only once backup
  is on (or a share is accepted), so the app runs normally without iCloud, signed out, or as an
  unsigned development build.
- `CKSyncEngine` state is saved on every `.stateUpdate` and restored on start, so launches
  don't refetch everything; each item keeps its record's system fields, so edits don't fail
  with `serverRecordChanged`.
- `zoneNotFound` recreates the zone and retries; `quotaExceeded` and a signed-out account show
  in Settings; switching to another Apple ID stops sync and never merges that account's data.
- A fetched asset sits at a temporary URL and is copied into `Media/` immediately.
- Removing a clip queues a CloudKit delete. **Delete iCloud backup** is separate from Delete
  all my data, and says plainly that deleting a shared year ends that film for everyone in it.

## Build order

1. Remove the server media path (web, Supabase, iOS) and restore the on-device privacy text.
2. `CloudSync`: record ↔ model mapping (pure, tested), the private-zone `CKSyncEngine`, restore.
3. Settings → Backup: iCloud status, the toggle, what's waiting, quota and signed-out states.
4. Sharing: create/fetch the zone share, `ShareLink` with `CKShareTransferRepresentation`,
   accept in the app delegate, a shared-database engine, and pulling contributors' clips in.
5. Entitlements: iCloud (CloudKit, `iCloud.com.yearfilm.app`), push, remote-notification
   background mode, `CKSharingSupported`.
