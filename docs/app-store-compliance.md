# App Store compliance

What App Store Connect and App Review require as of **October 2026**, and where
Yearfilm meets each requirement. Re-check before every submission; Apple revised
the Review Guidelines three times in 2026 (February, June, October).

> Sources are Apple's developer news and secondary coverage of it. Confirm
> each item against [developer.apple.com/app-store/review/guidelines](https://developer.apple.com/app-store/review/guidelines/)
> and [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)
> before submitting.

## Upload gates (App Store Connect rejects the build)

| Requirement | Status | Where |
|---|---|---|
| Built with **Xcode 26+ and the iOS 26 SDK** (required since Apr 28, 2026) | ✅ CI builds on `macos-26` with Xcode 26 | `.github/workflows/ios.yml` |
| Minimum deployment target **iOS 13+** (reported for Sep 2026; iOS 15+ reported for Apr 2027) | ✅ iOS 17.0 | `ios/project.yml` |
| **Privacy manifest** with a reason for every required-reason API | ✅ UserDefaults → `CA92.1`; no tracking; no collected data | `ios/Yearfilm/Resources/PrivacyInfo.xcprivacy` |
| Third-party SDKs ship their own manifests and signatures | ✅ none used | — |
| **Export compliance** answered | ✅ `ITSAppUsesNonExemptEncryption = NO` | `ios/project.yml` |
| 1024px app icon, no alpha | ⚠️ placeholder; replace before submission | `Assets.xcassets/AppIcon` |

## App Store Connect metadata (fill in at submission)

| Item | Value / action |
|---|---|
| **Age rating questionnaire** (new system; answers were required by Jan 31, 2026) | Answer every question. No user-generated content is shared between users in v1, no chat, no AI assistant → expect 4+. Revisit when family sharing ships (that is UGC under 1.2). |
| **Privacy nutrition label** | "Data Not Collected" is accurate for v1: everything stays on the device. Must change the day uploads or accounts ship. |
| **Privacy Policy URL** | https://yearfilm.com/privacy (`web/app/privacy/page.tsx`) |
| **Support URL** | https://yearfilm.com/support (`web/app/support/page.tsx`) |
| **Category** | Photo & Video |
| **Screenshots** | iPhone 6.9" set required. App is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), so no iPad screenshots needed. |
| **Accessibility nutrition labels** | Optional but shown on the product page. v1 supports Dynamic Type (system fonts throughout) and VoiceOver labels; test with both before declaring them. |
| **EU trader status (DSA)** | Must be declared to distribute in the EU. |

## Review Guidelines that apply to this app

**5.1.1 Data collection and storage**
- Purpose strings explain what access is *for*: the microphone is "your weekly voice
  note, which becomes the narration". ✅ `NSMicrophoneUsageDescription`
- Permissions are requested at the moment of use, never at launch: microphone on first
  record (`Recorder.start`), notifications from a button the person pressed
  (onboarding or Settings). ✅
- **No photo library permission at all.** `PhotosPicker` runs out of process and hands
  over only the picked videos; capture dates are read from the file itself
  (`MovieInfo.read`), not from `PHAsset`. ✅
- **Account deletion (5.1.1(v))**: v1 has no accounts. Settings → *Delete all my data*
  removes every clip and note. **When accounts ship, account deletion must be possible
  inside the app** and must delete server data too, not just sign out.

**5.1.2(i) Sharing data with third parties, including third-party AI** (Nov 2025)
- Apps must disclose where personal data goes, *including to third-party AI*, and get
  explicit permission first. Apps have been rejected for sending data to an AI API
  without asking.
- v1 sends nothing anywhere. The roadmap does: Whisper transcription of voice notes,
  music generation, face clustering. **Rule for this codebase:** any feature that sends
  a clip, voice note, transcript or face data off the device ships with a consent screen
  that names the service and what is sent, defaults to off, can be withdrawn in Settings,
  and leaves the app usable without it. Self-hosted processing on our own servers is
  still a third party from the user's point of view, so disclose it in the privacy policy.

**2.5.19 No hidden, dormant or undocumented features** (Oct 2026)
- Nothing ships behind a remote flag that App Review can't see. Features that aren't
  ready are not in the build, rather than shipped switched off.
- The Settings privacy text describes future third-party processing as a promise
  ("we'll ask first"), not as a control that does nothing.

**1.2 User-generated content** (tightened Feb and June 2026)
- Not applicable in v1: nothing one person adds is shown to anyone else.
- **Applies once family sharing ships**: contributors' clips appear to other family
  members. That needs a way to report and remove content, block a contributor, and a
  published contact. Nonconsensual intimate imagery (1.2, Oct 2026) must be prevented and
  removable. Scope it into the sharing feature, not after.

**4.3 Spam / low-value apps** (tightened June 2026)
- Apple now removes apps that don't attract users, and flags thin apps in saturated
  categories. A weekly video diary on its own reads as a 1SE clone. The submission should
  lead with what's different, the film, so the review notes and screenshots must show
  the Year view and premiere, not just a picker.

**3.1 Payments**
- v1 is free with no purchases. When a paid tier ships (for example, rendering the
  film), digital content bought in the app goes through In-App Purchase, subject to the
  current US link-out rules, which changed after the 2025 court decision.

**Children and families**
- The app is for adults filming their families; it is **not** in the Kids category, and
  the privacy policy says it isn't directed at children. Footage of children is still
  sensitive: keep it on-device or encrypted, and never use it for training or analytics.
- **Face recognition** needs consent per person, from a parent for a child, before
  clustering (`cast_members.face_consent_at` in `schema/schema.sql`). Illinois BIPA
  applies.

## Pre-submission checklist

- [ ] Real app icon, without transparency
- [ ] `DEVELOPMENT_TEAM` set; bundle ID `com.yearfilm.app` registered
- [ ] Age-rating questionnaire answered
- [ ] Privacy label = Data Not Collected (re-check against the code)
- [ ] Privacy and support URLs live on yearfilm.com
- [ ] Review notes: what the app does, that no login is needed, how to add a clip on a
      fresh simulator (drag a video into Photos first)
- [ ] TestFlight build tested with VoiceOver and the largest Dynamic Type size
- [ ] Every permission prompt triggered from the flow, never at launch
