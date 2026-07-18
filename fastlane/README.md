fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload to TestFlight

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Upload metadata and screenshots to App Store Connect

### ios privacy_labels

```sh
[bundle exec] fastlane ios privacy_labels
```

Declare App Privacy nutrition labels via App Store Connect API

### ios iap_setup

```sh
[bundle exec] fastlane ios iap_setup
```

Set IAP metadata (name + description) and pricing (USD base, auto-equalized globally)

### ios iap_diagnose

```sh
[bundle exec] fastlane ios iap_diagnose
```

Diagnose what is missing for each IAP (state, localizations, pricing, review screenshot)

### ios resubmit_with_iaps

```sh
[bundle exec] fastlane ios resubmit_with_iaps
```

Create a new review submission for the rejected v1.0 version, linking all 3 IAPs

### ios link_iaps

```sh
[bundle exec] fastlane ios link_iaps
```



### ios iap_reset

```sh
[bundle exec] fastlane ios iap_reset
```

Delete pending IAP submissions so localizations/pricing can be edited again

### ios iap_check_locs

```sh
[bundle exec] fastlane ios iap_check_locs
```

Check localizations via v1 IAP path (the actual path for these IAPs)

### ios iap_type_probe

```sh
[bundle exec] fastlane ios iap_type_probe
```

One-shot probe: test which relationship type Apple accepts for inAppPurchaseLocalizations

### ios submit

```sh
[bundle exec] fastlane ios submit
```

Submit existing build for App Store review

### ios release

```sh
[bundle exec] fastlane ios release
```

Full release: build → TestFlight → metadata → submit for review

### ios list_versions

```sh
[bundle exec] fastlane ios list_versions
```

List all App Store versions and their states

### ios debug_builds

```sh
[bundle exec] fastlane ios debug_builds
```

Debug builds API response

### ios check_builds

```sh
[bundle exec] fastlane ios check_builds
```

Check builds available in TestFlight and review submission items

### ios asc_state

```sh
[bundle exec] fastlane ios asc_state
```

Check current state of versions and IAPs

Read-only: list recent builds with processing state (plus versions/subs via check_state)

### ios create_v12

```sh
[bundle exec] fastlane ios create_v12
```

Create v1.2 in App Store Connect (now that v1.1 is READY_FOR_SALE and its train is closed) and bump the local marketing version to match. TestFlight-only — does not submit for review.

### ios check_state

```sh
[bundle exec] fastlane ios check_state
```



### ios submit_v11

```sh
[bundle exec] fastlane ios submit_v11
```

Create v1.1, cancel old submissions, attach latest build + all 3 IAPs, and submit for App Store review

### ios submit_v12

```sh
[bundle exec] fastlane ios submit_v12
```

Submit v1.2 for review — pass build_number: (defaults to latest VALID build tagged 1.2). Run `metadata` first.

### ios fix_review_notes

```sh
[bundle exec] fastlane ios fix_review_notes
```

Patch App Review notes on the current app version to match the corrected billing/AI-disclosure language

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
