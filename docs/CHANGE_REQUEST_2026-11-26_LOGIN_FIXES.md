# Simplek — Change Request, 26 Nov 2026: login, sign-up, log-out and fingerprint fixes

**For:** Claude Code, working in `D:\projects\simple_billing`.
**From:** the owner, after testing on his phone.
**Priority: do this next.** Finish the change you're on, then do this file before anything else
in the `CLAUDE.md` queue. Real users can get stuck and lose data because of these bugs.

Line numbers are from `lib/main.dart` and `lib/app_lock.dart` as of 26 Nov, 20:00. They may have
moved since.

## What the owner saw

1. On the phone he was signed in to an older account. He pressed Log out and it didn't seem to
   log out. After some tries it did.
2. He tried to create a new account on the phone and couldn't.
3. He created the account on the computer instead. Back on the phone, the old business was still
   showing.
4. The phone then got stuck on "Set your password". Clearing the cache didn't help, and there was
   no way back. When he set a password, it went to "Set up your business", although that business
   was already set up.
5. Every time he logs in with his password, the app asks for his fingerprint.

## Causes found in the code

| # | Cause | Where |
|---|---|---|
| A | **Fingerprint after a password login.** `_locked` is a `late` field, so it's only worked out on first read, in `build()`. But `initState()` resets `AppLock._unlockedThisSession` to false *before* that. So `markSignedInWithPassword()` never takes effect, and every password login opens the lock screen. "Log in with password instead" signs out and leads back to the same screen, so the user goes round in a loop. | `app_lock.dart` ~90 and ~98 |
| B | **An unfinished sign-up stays on the phone for ever.** `PendingSignup` (name, business, mobile) is saved on the phone when the sign-up email is sent. It's cleared only at the very end of business setup. `AuthGate` shows "Set your password" to **any account** that logs in on that phone while it exists. That includes a different account, and an account that already has a password. "Clear cache" doesn't remove it. Only "Clear storage" or reinstalling does. The page has no Back or Cancel. | `main.dart` `PendingSignup` ~552, `AuthGate.build` ~640 |
| C | **Business setup doesn't check the server.** After "Set your password", the app always opens `BusinessOnboardingPage`, even when the account already has a `business_profiles` row. `saveProfile()` then **upserts over the existing business profile**, so the real profile can be overwritten. | `PasswordSetupPage._setPassword` ~2585, `_finish` ~2966 |
| D | **"Sign up" with an email that already has an account resets its password.** `signInWithOtp(shouldCreateUser: true)` simply sends a login link to an existing account. The app saves `PendingSignup` anyway, so when the link is tapped it asks for a new password and then asks to set up the business again. This is the "reset password, then business profile" the owner saw. | `SignupPage._sendVerificationEmail` ~2285 |
| E | **Log-out leaves the old account on the phone.** `_confirmLogout` only calls `signOut()`. It doesn't catch an error, doesn't close open screens, and doesn't clear the local copy of the business. `AuthGate._refresh()` then calls `syncFromCloud()` without `clearIfMissing`. So if the next account has no business profile yet, the **previous account's business name, logo, bank details and GSTIN stay on screen**, and could go into its invoices. | `_confirmLogout` ~1178, `AuthGate._refresh` ~607, `syncFromCloud` ~4662 |
| F | **Sign-up email can't reach customers.** The live Supabase project has no custom SMTP. Without it, Supabase sends auth emails only to members of the project's team, at most 2 per hour. So sign-up fails for real customers and after a couple of tries for the owner. The app shows a generic message, so nobody can tell why. | Supabase settings, not code; and the error text ~2310 |

## Fixes

### L1. Fingerprint only when the app is opened with a saved login (cause A)

- In `_AppLockGateState.initState()`, work out `_locked` first, then reset the flag:
  `_locked = AppLock.enabled.value && !AppLock._unlockedThisSession;` and only then
  `AppLock._unlockedThisSession = false;`. Make `_locked` a normal field, not `late`.
- Call `markSignedInWithPassword()` only **after** `signInWithPassword` succeeds, not before it.
- Rule: a password login never asks for the fingerprint. The fingerprint is asked only when the
  app opens with a saved login, or comes back after more than 45 seconds in the background.
- The "Unlock faster next time?" offer still appears once, after the first password login.
- Quick unlock is stored per account, not per phone. Key it by user ID, for example
  `app_lock_enabled_<userId>`. A different account logging in on the same phone doesn't inherit it.
- Tests:
  - lock on + password login → no lock screen;
  - lock on + app restarted with a saved session → lock screen;
  - "Log in with password instead" → login → no lock screen, so no loop.

### L2. An unfinished sign-up can't trap anyone (cause B)

- `PendingSignup.save` also stores the **email** and the **time**.
- `AuthGate` uses a pending sign-up only when **all** of these are true. Otherwise it deletes the
  pending sign-up and carries on to the normal app:
  - the signed-in email equals the saved email;
  - it was saved less than 24 hours ago;
  - the account has no password yet (`user_metadata.password_set` is not true, see L3);
  - this login came from the email link, not from a password login.
- `PasswordSetupPage` gets a **"Cancel and log out"** button. It deletes the pending sign-up and
  signs out, so the user is never stuck.
- Log-out (L4) also deletes any pending sign-up.

### L3. Set-up screens follow the server, not the phone (causes C and D)

- When "Set your password" succeeds, also save `password_set: true` in `user_metadata`. Old
  accounts that log in with a password count as having one.
- After the email link signs someone in, check the server, not the phone:
  - **The account already has a password or a business profile** (that is, it's an existing
    account): don't ask for a password or business set-up. Delete the pending sign-up and open
    Home, with the message "You already have a Simplek account. You're now logged in."
  - **New account:** "Set your password", then "Set up your business", as today.
- Any time an owner account is signed in with **no** `business_profiles` row, show "Set up your
  business". This covers sign-ups finished on another device. Skip it for an accountant whose
  account has businesses shared with it (`BusinessAccess.sharedWithMe()` not empty). They work in
  those businesses.
- `BusinessOnboardingPage` gets a **"Log out"** link at the top, so there is always a way out.
- **Never overwrite a saved business profile from set-up.** In `_finish()`, check the server
  first. If a row already exists, don't save. Load that profile and go to Home.
- After set-up finishes, go straight to Home. Don't sign out and ask for the new password again.
  The user has just set it, and the extra login is where the fingerprint loop started.

### L4. Log-out really logs out, and clears the old account (cause E)

Write one `signOutEverywhereOnThisDevice()` function. Use it for both Log out buttons, "Log in
with password instead", and anything else that signs out. It:

1. Checks for unsynced items in `OfflineStore` for this account. If there are any, the log-out
   dialog says "N items haven't reached the server yet. Log out anyway? They'll upload next time
   you log in to this account." Unsynced items stay on the phone, kept under their account as
   today. **Never delete them.**
2. Calls `signOut()` inside try/catch. If the network call fails, it still removes the session
   saved on the phone, so the user is logged out on this phone either way.
3. Clears this account's local copy:
   - the business profile keys in SharedPreferences and secure storage, and the downloaded logo,
     signature and QR files;
   - the in-memory notifiers (`profile`, `isGstRegistered`, the terms, `defaultDueDay`);
   - `BusinessAccess.viewing`, `ListPrefs`, the pending sign-up and LiveSync subscriptions.
4. Closes every open screen (`popUntil(isFirst)`), so the login screen is what's left.

Also:
- On every login, `AuthGate` calls `syncFromCloud(clearIfMissing: true)`, so a new account never
  shows another account's details.
- Save the last signed-in user ID on the phone. If a **different** user ID signs in, for example
  because the old session ran out without a log-out, run step 3 first.

### L5. Sign-up on the phone: clear messages (cause F)

- Show the real reason from Supabase. Map the common ones to plain words:
  - rate limit → "Too many sign-up emails were sent in the last hour. Please try again later.";
  - address not allowed or other email errors → "We couldn't send the email right now. Please try
    again later, or contact support.".

  Keep the full error in the debug log.
- On "Check your email", add: "Open the link on this phone. If you open it on a computer, sign up
  there instead." (A link opened on a computer can't open the phone app.)
- Check that `simplek://login-callback/` and the web app's address are listed in Supabase →
  Authentication → URL Configuration → Redirect URLs. Write the result in `NOTES.md`.
- **Owner action, not code:** set up custom SMTP in Supabase (see "Owner's part" below). Until
  then, sign-up can't work for customers.

## Done checklist

- [ ] L1–L5 done, each as its own commit, with tests:
      - the lock-screen cases in L1;
      - pending sign-up for a different email, an old one, and a password login is ignored and
        deleted;
      - set-up is skipped when a profile exists, and `_finish()` never overwrites one;
      - log-out clears the profile, and a second account sees a blank profile, not the first one.
- [ ] Hand test on the phone (Android), written in `CHANGE-STATUS.md`:
  1. log in as account A, log out → login screen; log in as B → none of A's business details;
  2. start sign-up on the phone for an email that already has an account, tap the link on the
     phone → "You already have a Simplek account", Home; no password page or set-up page; the
     business profile is unchanged;
  3. start sign-up on the phone, then log in as another account → normal Home, no "Set your
     password";
  4. quick unlock on: password login → no fingerprint; close and reopen the app → fingerprint
     once;
  5. on "Set your password" and "Set up your business", the Cancel and Log out options work.
- [ ] `flutter analyze` and `flutter test` pass. Screenshots sent to the owner before pushing to
      `master`.

## Owner's part (no code)

**Custom SMTP.** In the Supabase dashboard go to Authentication → Emails → SMTP Settings. Once
it's on, the email limit goes up (to 30 an hour at first, and it can be raised) and emails reach
anyone. A domain isn't needed to start: Gmail's SMTP with an app password, or a free Brevo
account, works. Move to `simplek.in` email once the domain is live. The super admin panel's email
settings (`CHANGE_REQUEST_2026-11-26_SUPER_ADMIN.md`) are for Simplek's own emails, so Supabase
login emails still need this setting.

**To free the phone right now,** before the fix: Android Settings → Apps → Simplek → Storage →
**Clear storage** (not just Clear cache). Then open the app and log in to the new account with its
password. Clear storage also deletes anything on the phone that hasn't reached the server yet. If
More → Sync and backup shows items waiting, let them upload first.
