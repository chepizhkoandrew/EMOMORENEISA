# Professor Madrid — App Store & Landing Site

## Phase 1: Landing Site (DONE ✓)

### [x] Step: Build & deploy the landing site
- Created `site/index.html` — one-pager with Professor Madrid dog mascot, animated greeting, Spanish verb popup
- Pushed to GitHub: https://github.com/chepizhkoandrew/professormadrid
- Deployed to Vercel: https://professormadrid.vercel.app
- Added custom domains `professormadrid.com` and `www.professormadrid.com` to Vercel project
- Set GoDaddy DNS: A record `@` → `76.76.21.21`, CNAME `www` → `cname.vercel-dns.com`
- Both domains verified by Vercel ✓

## Phase 2: App Store Release

### [x] Step: Rename app to "Professor Madrid" and prepare metadata
- Bundle ID changed to `com.professormadrid.app` in both Debug and Release configs
- `INFOPLIST_KEY_CFBundleDisplayName = "Professor Madrid"` set in project.pbxproj
- API keys moved out of `Info.plist` to `$(GEMINI_API_KEY)` and `$(OPENAI_API_KEY)` vars
- `Secrets.xcconfig` gitignored
- App Store description written: `fastlane/metadata/en-US/description.txt`
- Keywords, subtitle, support/privacy/marketing URLs created ✓

### [x] Step: Process screenshots for App Store
- 13 screenshots renamed from UUID filenames to descriptive names in `appstore/screenshots/`
- Resized to 1290×2796 (6.7" iPhone) in `appstore/screenshots/iPhone67/` ✓

### [x] Step: Privacy Policy page
- `site/privacy.html` created with full GDPR-compliant policy
- Deployed to Vercel with cleanUrls routing
- Live at https://professormadrid.com/privacy ✓

### [x] Step: Fastlane automation
- `fastlane/Appfile` — bundle ID, team ID, Apple ID
- `fastlane/Fastfile` — 4 lanes: `beta`, `metadata`, `submit`, `release`
- `fastlane/metadata/en-US/` — name, subtitle, description, keywords, URLs, release notes
- App Store Connect API key configured (Key ID: V86ZAHA4K5)
- `Gemfile` created for consistent fastlane version
- `.gitignore` updated to protect `Secrets.xcconfig` and `appstore/keys/` ✓

### [x] Step: App Store Connect setup
- Bundle ID `com.professormadrid.app` registered ✓
- App record created (App ID: 6782026883) ✓
- Build 1.0 (2) uploaded to TestFlight and processed ✓
- Metadata uploaded: description, keywords, subtitle, URLs, copyright "2026 priroda.tech" ✓
- 13 screenshots uploaded (1290×2796) ✓
- App review contact info set (Andrii Chepizhko, +380 68 072 1898) ✓
- All precheck rules passing ✓

### [ ] Step: Fix login (Supabase OAuth — MANUAL)
- Go to https://supabase.com/dashboard/project/rbbgayxvrobzlndprcwt/auth/providers
- Apple provider → set Bundle ID to `com.professormadrid.app`
- Google provider → add iOS client ID `353195660969-ff6luandfvauj7odempe0k2imsnh98k5.apps.googleusercontent.com` to Authorized Client IDs
- Verify login works in TestFlight

### [ ] Step: Submit for App Store review
- After login is verified working: `fastlane ios submit`
- Set age rating, category (Education), pricing in App Store Connect if not done
- Monitor review status at https://appstoreconnect.apple.com/apps/6782026883
