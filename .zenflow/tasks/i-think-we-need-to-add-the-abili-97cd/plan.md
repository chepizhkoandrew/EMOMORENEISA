# Email/Password Sign-In + Test User + New User Treats

Add email/password authentication to the iOS app (for TestFlight testers without Apple ID), create the initial test user, and verify the 250-treat trial grant is in place for all new users.

### [x] Step 1: iOS — email/password sign-in
- Add `signInWithEmail(email:password:)` to `AuthService.swift` using `supabase.auth.signIn(email:password:)`
- Update `SignInView.swift` with a "Continue with Email" button that expands inline to email + password fields + yellow "Sign In" button + cancel link

### [x] Step 2: Create test user script
- Add `server/scripts/create-test-user.mjs` that calls `supabase.auth.admin.createUser` with `spanishlearnerua@professormadrid.com` / `UD78SNN.4x,-$S9` and `email_confirm: true`
- Handles "already exists" gracefully by updating password

### [x] Step 3: New-user trial treats (already in place)
- `config.js` already sets `trialGrantTreats: 250` as default for `TRIAL_GRANT_TREATS`
- `grantTrialIfNeeded` in `wallet.js` credits 250 treats on first `/v1/bootstrap` call — applies to all sign-in methods including email/password
