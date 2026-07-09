# App Store Release Plan

## What was ready
- App Store Connect API key: `appstore/keys/AuthKey_V86ZAHA4K5.p8`
- Fastfile with `beta`, `metadata`, `submit`, and `release` lanes
- Metadata in `fastlane/metadata/en-US/` (name, subtitle, description, keywords, copyright, URLs, release notes)
- Screenshots in `appstore/screenshots/en-US/iPhone65/` and `appstore/screenshots/en-US/iPhone67/` (13 each)
- App icon at `appstore/app_icon_1024.png`

## Fix applied
Corrected two path bugs in the `metadata` lane of `fastlane/Fastfile`:
- `screenshots_path` was `"../appstore/screenshots"` → fixed to `"appstore/screenshots"`
- `metadata_path` was `"metadata"` (empty folder) → fixed to `"fastlane/metadata"`

## Release steps

### [x] Step: Fix path bugs in Fastfile metadata lane

### [x] Step: Build and upload to TestFlight
Build 48 uploaded (iPhone-only, `TARGETED_DEVICE_FAMILY = "1"`).
Fixed `import Supabase` missing in `AnalyticsService.swift`.

### [x] Step: Upload metadata and screenshots to App Store Connect
Metadata, screenshots, age rating, privacy labels, keywords all uploaded.

### [x] Step: Submit for App Store review
Build 1.0 (48) submitted. Currently in review.

### [x] Step: Fix IAPs and resubmit with build 77
1. All 3 IAP packs set to `READY_TO_SUBMIT` ✅
2. Build 77 (latest code: full-screen paywall/profile, picker fixes, UIBackgroundModes fixed) uploaded and linked to v1.0 ✅
3. Submission `3e864217` is `READY_FOR_REVIEW` with v1.0 + all 3 IAPs ✅

### [ ] Step: After Apple approval — apply Supabase migration
Apply migration to update product IDs in the server config:
```
supabase/migrations/20260703100000_update_iap_product_ids.sql
```
