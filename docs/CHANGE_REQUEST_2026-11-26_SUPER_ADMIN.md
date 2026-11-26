# Simplek — Change Request, 26 Nov 2026: Super admin panel, plans and usage

**For:** Claude Code, working in `D:\projects\simple_billing`.
**From:** the owner, preparing to sell Simplek online.
**Read first:** `CLAUDE.md`, `BUILD-STANDARDS.md` (sections 4, 5, 9, 11, 13 and 15) and
`docs/PROJECT_SUMMARY.md`.
**Order:** do this **after** the three files already in the `CLAUDE.md` work queue. It uses
the audit log and soft delete from `CHANGE_REQUEST_2026-11-25_STANDARDS.md` B1 and the new look
from `UI_REDESIGN_2026-11-25.md`.

**Why:**
- the owner needs one place to see every business: who is active, their last invoice, their plan
  and usage;
- he needs to change plans and manage the platform settings (email, WhatsApp, Razorpay);
- today he can't even remember which real businesses he has enrolled, or their login emails.

**Today:**
- there are **no plans and no admin area**: every account is free and unlimited
  (`PROJECT_TRACKER.md`);
- the website advertises "Free up to 30 invoices a month";
- the owner now wants **250 free invoices**, so the website must be updated once he confirms the
  details (see S4).

---

## S0. Where it lives and who can open it

1. **Web only:** a new **Admin** area inside the existing web app at
   `https://simplek.pages.dev/app/#/admin`. There's nothing in the phone app.
2. **Who:** only users listed in a new `super_admins` table (`user_id`, `added_at`, `added_by`).
   - The first entry is the owner's login email. Put a placeholder in `NOTES.md` under "Replace
     before launch"; the owner adds his email.
   - Everyone else gets "Page not found", not "Access denied", so the area isn't advertised.
3. **Checked on the server, every time:**
   - an `is_super_admin()` SQL function;
   - all admin data comes from `security definer` functions and edge functions that call it
     first;
   - row-level security on the new tables.
   - Hiding the menu in the app is not protection.
4. **Two-step login for super admins:** Supabase Auth TOTP (an authenticator app).
   - Required before the Admin area opens.
   - Offer to set it up on the first visit.
5. **Every admin action is written to `audit_log`** (from B1) with who, what, when, which
   business, and old and new values. For example: plan changed, password reset, business
   suspended, setting changed, support view opened.
6. **Look:** the new design (navy, orange, sky; labels above fields; press feedback).
   - A left sidebar: Dashboard, Businesses, Users, Plans, Integrations, Audit log, Platform
     settings.
   - An orange "ADMIN" badge in the top bar, so it's never mistaken for a business account.
   - See `docs/design/AdminDashboard.png`.

---

## S1. Dashboard

**Tiles** for the chosen period (Today, 7 days, 30 days, This month, Custom), computed on the
server from **all** rows:
- businesses enrolled;
- **active businesses**: at least one invoice in the period;
- new sign-ups;
- invoices created;
- businesses **near the free limit** (80% or more);
- businesses **over the limit**;
- businesses on each plan;
- monthly recurring revenue from paid plans (₹0 until payments exist).

**Charts:** sign-ups per month, and invoices per month, for the last 12 months.

**Lists:**
- "Recently active": the last 10 businesses by last invoice;
- "Gone quiet": businesses with no invoice in 30+ days that had one before;
- "Needs attention": over the limit, or the GSTIN lookup failing.

Each row opens the business.

---

## S2. Businesses (the owner's main page)

A list that follows BUILD-STANDARDS section 5: server-side pages of 25, search across everything,
filters, sort, export to Excel and CSV.

**Columns:**
- Business name; owner name;
- **login email**; **mobile**;
- GST registered (Yes or No); city and state;
- **Plan**; **invoices used / limit**, e.g. "212 / 250", with a bar that turns orange from 80% and
  red when over;
- **last invoice date**; **last login**; joined date;
- status: Active, Suspended or Deletion pending.

**Filters:** plan, status, GST yes/no, "no invoice in 30 days", "near or over the limit", joined
between dates.

**Business detail page:**
- **Summary:** business profile (name, GSTIN, address, contact), owner's email and mobile, joined
  date, last login, last invoice, totals (invoices, customers, items), and a 12-month usage chart.
- **People:** the owner, plus every accountant with access (email, date given).
- **Plan:**
  - current plan, start date, end date or renewal date, invoices used against the limit;
  - **Change plan:** pick a plan, start date, optional end date, optional **extra free invoices**,
    and a required reason;
  - the plan history underneath.
- **Admin notes:** private notes with dates, e.g. "Called on 26 Nov; wants Tally help".
- **Actions**, each confirmed and logged:
  - **Reset password** (see S3);
  - **Suspend / Reactivate**: suspended businesses can log in only to a screen saying "Your
    account is paused. Contact support", and their data is untouched;
  - **Support view (read-only)**: opens the business in the same read-only mode accountants use,
    with a banner "Admin support view";
  - **Download business data** (the B4 ZIP);
  - **Start account deletion** (the B4 30-day flow);
  - quick **Call / WhatsApp / Email** links on the mobile and email.

---

## S3. Users and logins: one email = one account

**Owner's rule:** the **email is the login and the identity**. One email belongs to one account.
The same email can't create a second account or a second business.

**Build:**
1. Supabase Auth already refuses a second account with the same email. Also:
   - **one business per owner:** a unique constraint on `business_profiles` owner `user_id` (check
     the existing data first);
   - store emails in lowercase and trimmed (BUILD-STANDARDS section 1), so `A@x.com` and `a@x.com`
     are the same person;
   - sign-up with an email that exists says "This email already has an account. Log in instead."
   - Accountant access stays as it is: an accountant logs in with their own email and views
     businesses that invited them. That is not a second account.
2. **Users page:** every login email, with:
   - name and mobile;
   - role: owner of which business, or accountant for which businesses;
   - joined date, email confirmed (Yes or No), last login, two-step login on or off, status.
   - Search, filter and export.
3. **The owner's current problem** (he forgot which businesses and logins he created):
   - this page and S2 show every business with its login email and mobile;
   - **passwords can never be shown.** Supabase stores only a one-way hash; nobody, including the
     admin, can read a password. That's deliberate and must stay so.
   - Instead, **Reset password** (super admin only) runs an edge function that calls the Supabase
     Admin API `updateUserById`:
     - it sets a **temporary password**, shown to the admin **once**, for him to pass on by phone or
       WhatsApp;
     - it sets `must_change_password = true` in the user's metadata;
     - at the next login the app forces a "Set a new password" screen before anything else;
     - logged in `audit_log`.
   - When custom email is set up later (S5), add "Send reset link" as a second choice.

---

## S4. Plans, the free limit and how invoices are counted

**Owner decided:**
- **250 invoices are free**;
- **deleted and cancelled invoices still count**: each invoice number issued counts once, so
  deleting one doesn't give a free invoice back.

**Build:**
1. **`plans` table**, editable on the Plans page:
   - name, monthly price, yearly price;
   - **invoice limit** and **limit period**: `lifetime`, `monthly` or `none`;
   - features (accountant access, Tally export, and so on, as on/off flags for later);
   - visible to new sign-ups (yes or no); active.
   - **Seed:**
     - **Free**: 250 invoices, period `lifetime` (**owner to confirm** whether it's 250 in total or
       250 per month; it's one setting either way);
     - **Unlimited**: ₹250 a month or ₹1,500 a year (from the website), no limit.
2. **`business_plans` table:** business, plan, start date, end date, extra invoices granted,
   reason, changed by, changed at. The current plan is the latest row in effect. New sign-ups get
   the Free plan automatically.
3. **Usage counting, on the server:** "invoices used" means the number of invoices **ever created**
   by the business within the plan's period.
   - It **includes soft-deleted invoices** (B1) and any cancelled ones.
   - Counted from the invoices table, including deleted rows, not from what's visible.
   - Drafts don't count.
4. **Enforcement:**
   - `save_invoice` refuses a **new** invoice when the business is at its limit plus extra
     invoices. Editing existing invoices is always allowed.
   - The message: "You've used all 250 free invoices. Upgrade to keep creating invoices." with an
     **Upgrade / Contact us** button. Until online payment exists, it opens WhatsApp or email to
     the owner.
   - In-app notices at 80% and 95% ("You've used 200 of 250 free invoices").
   - **A Platform setting "Enforce plan limits" starts OFF**, so no real user is blocked
     unexpectedly. The owner turns it on when ready. Usage is counted and shown either way.
5. **For the user:** in Settings, "Your plan: Free · 212 of 250 invoices used", with an Upgrade
   button.
6. **Website** (`website/index.html`, Pricing section): today it says "Free: up to 30 invoices a
   month". Change it to match the confirmed free limit **only after the owner confirms the
   wording**; list it in `NOTES.md`.

---

## S5. Integrations (platform settings for email, WhatsApp and Razorpay)

These belong to Simplek itself, not to each business. For example: Simplek's own emails and
WhatsApp messages, and later, collecting plan payments through Razorpay. Follow BUILD-STANDARDS
9.1 and 13.1.

**Secrets:**
- stored **encrypted on the server** (Supabase Vault), never sent to the browser;
- shown masked (`••••1234`) after saving, with a **Replace** button;
- every change written to `audit_log`.

1. **Email**
   - **Provider:** SMTP / Gmail or Google Workspace / Brevo / Amazon SES / Zoho.
   - **Fields:** host, port, security (SSL/TLS), username, **password or API key (secret)**, From
     name ("Simplek"), From address, Reply-To.
   - **Send test email** to an address typed by the admin. Show "Connected", or the exact error.
   - **Gmail note** on the page: personal Gmail needs 2-Step Verification and an **App Password**,
     and has a low daily sending limit. Google Workspace or Brevo suit volume better.
   - Supabase Auth's own emails (sign-up link, and later password reset and OTP) are configured in
     the **Supabase dashboard**, not here. Show a short note with the steps, so the owner points
     both at the same email account.
2. **WhatsApp** (Meta WhatsApp Cloud API first; Gupshup, Interakt, AiSensy and Wati as later
   options)
   - **Fields:** WhatsApp Business number, Phone number ID, WhatsApp Business Account ID,
     **access token (secret)**, webhook verify token, webhook URL (read-only, to copy).
   - **Templates table:** name, language, category (Authentication, Utility or Marketing), approval
     status.
   - **Send test message** to a number typed by the admin.
3. **Razorpay**
   - **Mode:** Test / Live. Switching to Live warns and asks for confirmation.
   - **Fields:** Key ID (test and live), **Key secret (secret)**, **webhook secret (secret)**,
     webhook URL (read-only).
   - **Test connection:** creates and cancels a ₹1 test order.
   - Test mode shows a visible "Test mode" banner in the admin area.
   - Taking payment for plans, with an upgrade checkout, is **a later change**. This change only
     stores and tests the settings.
4. **Nothing is sent yet** by these integrations, except the test buttons. Wiring real messages
   (invoice emails, reminders) comes in later changes. Then add the "Messages sent" log from
   BUILD-STANDARDS 13.4.

---

## S6. Platform settings and audit log

- **Platform settings:**
  - **Enforce plan limits** (on/off, default off);
  - **New sign-ups open** (on/off);
  - **Notice banner for all users** (text, colour, start and end time), e.g. "Maintenance tonight
    at 11 pm";
  - **Support contact** (WhatsApp number and email) used by the Upgrade and Suspended screens.
- **Audit log page:** every admin action and the key user events (invoice delete or edit from B1,
  accountant access given or removed), with search, filters and export. Read-only; nothing can be
  deleted.

---

## S7. Privacy (fits B4)

Super admins can see business and personal data. So:
- add to the Privacy Notice: "Authorised Simplek staff can view your account details to provide
  support. Every such view is logged.";
- support view is read-only, logged, and shows its banner;
- use two-step login for admins (S0.4);
- exports of business lists are logged.

---

## Done checklist

- [ ] Migrations, each with a unique 14-digit version and a dry run first: `super_admins`,
      `plans` (seeded), `business_plans` (Free for every existing business), `admin_notes`,
      platform settings, Vault secrets, the one-business-per-owner constraint, and the usage and
      dashboard functions. Add regression tests in `supabase/tests/` proving that a non-admin
      **cannot** call any admin function or read any admin table.
- [ ] The edge function for **Reset password** (temporary password plus `must_change_password`),
      and the forced "Set a new password" screen in the app.
- [ ] The usage count includes deleted invoices. The limit is enforced only when the platform
      switch is on. Tested both ways.
- [ ] Every admin list follows BUILD-STANDARDS section 5, and every form section 1.
- [ ] Each change committed separately. `CHANGE-STATUS.md` updated. `NOTES.md` lists: the owner's
      admin email, whether 250 is in total or per month, the website pricing wording, and the
      email, WhatsApp and Razorpay accounts he must create.
- [ ] Screenshots of every admin page sent to the owner before pushing to `master`.
