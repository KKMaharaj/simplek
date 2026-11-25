# Simplek — Change Request, 25 Nov 2026 (part B: gaps against BUILD-STANDARDS.md)

**For:** Claude Code, working in `D:\projects\simple_billing`.
**From:** the owner's decisions on `docs/STANDARDS_GAP_REVIEW.md` (25 Nov, 23:42).
**Read first:** `CLAUDE.md`, `BUILD-STANDARDS.md` and `docs/PROJECT_SUMMARY.md`.
**Do this after** `docs/CHANGE_REQUEST_2026-11-25.md`. Where this file differs from the standard,
this file wins.

**Not in this file:** the Play Store app ID and signing key. The owner's developer will do these.

---

## B1. Invoices can be edited and deleted, with a GST warning (no per-invoice snapshot)

**Owner decided:** it's the business's own data, so they may edit or delete anything. Do **not**
build the standard's per-invoice snapshot (BUILD-STANDARDS 8.2). Instead, a GST-registered business
gets a clear warning.

**Build:**
1. **Delete invoice** (new): in the Invoice view ⋮ menu and the list ⋮ menu.
   - Implement as a **soft delete**: a `deleted_at` column plus `deleted_by`, set through a new
     server function that checks the owner.
   - Deleted invoices disappear from every list, total, report, GSTR-1 and export, and from
     outstanding balances. Their payments are hidden with them.
   - The number is **never reused**; the counter keeps going.
   - Show an **Undo** toast for 10 seconds.
   - Keep the row in the database. The standard says never to delete history; this keeps the
     owner's "delete" while staying recoverable.
   - Accountants (view-only) can't delete.
2. **Warnings** (one shared dialog). The extra GST line appears only when
   `BusinessSettings.isGstRegistered` is true:
   - **Delete:**
     - title "Delete invoice INV/2026-27/24?";
     - body "It will be removed from your invoices, totals and reports.";
     - for GST businesses, a highlighted line: **"If this invoice is already included in a GST
       return (GSTR-1), deleting it will cause differences in your GST filings."**;
     - buttons "Cancel" and "Delete".
   - **Edit:** when opening Edit on an invoice older than today, for GST businesses only: "Changes
     to this invoice may cause differences in GST returns you've already filed." Buttons "Cancel"
     and "Edit anyway". Show it once per edit, not on every keystroke.
   - **Business profile and products:** on saving changes to the business name, address, GSTIN,
     bank or UPI details, or a product's HSN/SAC or GST rate, show a one-line note: "Old invoices
     will also show the new details when you open or share them again." Add for GST businesses:
     "…which may not match GST returns you've already filed."
3. Record each delete and edit of an invoice in an **audit log** (`audit_log` table: who, what,
   when, invoice id, old values as JSON). It isn't shown in the app yet, but it helps settle any
   dispute.

**Check:**
- A GST business deletes an invoice: the warning shows the GST line; the invoice vanishes from the
  list, Home, Reports and GSTR-1; Undo brings it back.
- The next invoice number continues; the deleted number isn't reused.
- A non-GST business sees the warning without the GST line.

---

## B2. Totals, reports and lists use all the data (BUILD-STANDARDS section 5)

**Today:**
- Home adds up only the newest 100 invoices.
- Reports and GSTR-1 use only the newest 500 (5,000 lines).
- Lists load up to 200 rows at once.

**Build:**
1. **Totals on the server.** New SQL functions (security definer, checking business access)
   return totals over **all** matching invoices:
   - `dashboard_totals(from, to)`: to collect, total sales, collected, invoice count, partly paid
     count;
   - `report_summary(from, to)`, plus the customer-wise, item-wise and GSTR-1 tables, all
     computed in SQL.
   - Home, Reports and exports call these; nothing adds up rows in the app any more.
   - Deleted invoices (B1) and drafts are excluded.
2. **Lists** (Invoices, Quotations, Customers, Items, Payments) **paginate on the server**:
   - 25 rows by default, with a choice of 10 / 25 / 50 / 100, remembered per user;
   - "Showing 26–50 of 287" with ‹ Prev 1 2 3 … Next › on web; on phones, infinite scroll in
     pages of 25, with "Page 2 of 12" in the list header.
3. **Search and filters cover the whole list,** not just the loaded page. Changing a filter goes
   back to page 1.
4. **On web,** the page, filters and sort are kept in the URL, so Back and refresh return to the
   same view.
5. **Date filter presets** for Invoices and Reports: Today, Last 7 days, This month, This quarter,
   This year, Custom.
6. **Exports** (PDF, Excel, CSV, Tally) include **every** row matching the filter, with the filter
   and the date printed at the top.
7. Status badges always have words; colour is never the only signal.

**Check:** with a test account of 600+ invoices, Home and Reports totals equal a direct SQL sum.
Page 13 of a list loads quickly, and search finds an invoice from page 20.

---

## B3. Money and rounding (BUILD-STANDARDS 8.1)

**Today:** amounts are worked out with `double` in the app, and CGST/SGST can be 1 paisa off the
tax (5% on ₹101 → ₹2.53 + ₹2.53 against a tax of ₹5.05).

**Build:**
1. **All money maths in integer paise** in Dart: one `Paise` helper in `lib/money.dart`, no
   `double` for money anywhere.
   - Postgres `numeric(…, 2)` columns stay as they are. They are exact decimals, so the standard's
     "never floats" holds. Convert at the boundary only.
2. **One documented rounding rule.** Write it in `NOTES.md` and as a comment in `money.dart`:
   - line taxable value = quantity × rate, rounded half-up to the paisa;
   - line tax = taxable value × GST % ÷ 100, rounded half-up to the paisa;
   - intra-state: **CGST = tax ÷ 2 rounded half-up; SGST = tax − CGST**, so they always add up
     exactly (₹5.05 → ₹2.53 + ₹2.52);
   - invoice totals are sums of the line values;
   - round off to the rupee as decided on 19 Nov.
   - The PDF's rate-wise CGST/SGST lines are sums of the line values.
3. Amount in words always uses the printed total payable.
4. **The server repeats the same maths** when saving (`save_invoice`), and rejects a mismatch
   between the app's and the server's totals.
5. Invoices already saved keep their stored amounts. The rule applies to new and edited invoices.
6. Unit tests for the 5% on ₹101 case, the 3 × ₹33.33 @ 18% case, a 0% line, a mixed-rate invoice,
   and a ₹1.25 crore invoice.

---

## B4. Privacy: DPDP Act 2023 and DPDP Rules 2025 (BUILD-STANDARDS section 12)

**Timing:** the Rules were notified in November 2025. The core duties (privacy notice, consent and
individuals' rights) apply from **May 2027**. Build them now, before paid plans start. **A lawyer
must review the final notice and terms before launch**; list that in `NOTES.md` under "Needs
owner's confirmation".

**Roles:**
- For each **business owner's own account data** (name, email, mobile, login), Simplek is the
  **Data Fiduciary**.
- For the **business's customer records** (their customers' names, phones, GSTINs, addresses),
  the business is the Data Fiduciary and Simplek processes the data **on its behalf**. Say so in
  the Terms.

**Build:**
1. **Privacy Notice page** at `simplek.pages.dev/privacy`, in plain English. Link it from the
   website footer, the sign-up screen, the login screen and Settings. It must say:
   - who we are, with contact details;
   - exactly what personal data we collect and why (account, business profile, the customer data
     the business enters, device data for login);
   - who receives it: Supabase (hosting), the GSTIN lookup provider, Cloudflare (website), the
     accountants the business invites;
   - where it's stored and for how long;
   - how to withdraw consent, use your rights, and complain to us and to the Data Protection
     Board of India;
   - the notice version and date.
2. **Terms of Service page** at `/terms`, including the processing of customer data on the
   business's behalf. Link it with the Privacy Notice.
3. **Consent at sign-up:**
   - an **unticked** box: "I am 18 or older and I agree to the Privacy Notice and Terms" (with
     links); sign-up can't continue until it's ticked;
   - store each consent in a `consents` table: user, date and time, notice version, source (web or
     Android), IP or device;
   - existing users see a one-time "We've updated our Privacy Notice" screen to accept on their
     next login.
4. **Settings → "Your data and privacy":**
   - **Download my data:** a ZIP with everything (customers, items, invoices, quotations,
     payments and the business profile as Excel and JSON, plus every invoice PDF). Built on the
     server, delivered by an expiring link.
   - **Correct my data:** links to the profile and settings screens, which already exist.
   - **Delete my account** (this also withdraws consent):
     - first a clear warning to download the data, because GST law needs invoices kept for years;
     - confirm by typing the business name;
     - then 30 days of grace, during which logging in cancels the deletion;
     - then all personal data is deleted.
     - Security logs are kept for 1 year, then removed.
   - **Nominate a person** who can use these rights if the owner dies or can't act: name, relation,
     email or mobile.
   - **Raise a concern:** a form that goes to a `privacy_requests` table and emails the grievance
     contact. Each request gets a 30-day due date and the user sees its status.
5. **Grievance contact:** show a named contact person and email on the Privacy Notice and in
   Settings. Placeholder until the owner gives one; list it in `NOTES.md` under "Replace before
   launch".
6. **Retention:**
   - a daily clean-up job removes sign-ups never completed after 30 days;
   - accounts in their deletion grace period are deleted on day 31;
   - a user's data in the `audit_log` (B1) is kept 1 year after account deletion, then anonymised.
7. **Security, written down in `docs/SECURITY.md`:**
   - HTTPS everywhere;
   - encryption at rest (Supabase);
   - row-level security on every table (already in place);
   - access and security logs kept for at least 1 year;
   - accountant access logged.
8. **Breach plan:** `docs/BREACH-RESPONSE.md`:
   - contain the breach, assess it, and inform affected users without delay;
   - report to the Data Protection Board within 72 hours;
   - name who does what.
9. **Web storage notice:** the web app uses only essential storage (login), so show a small
   information bar with "OK" on first visit. No analytics or tracking without a real Accept/Reject
   banner.
10. **Collect only what's needed:** check that every field asked at sign-up and in the profile has
    a use. Optional fields are marked "(optional)".

**Check:**
- A new sign-up can't proceed without the tick, and its consent row is stored.
- Download my data produces a ZIP that opens, with matching counts.
- A deletion request cancels if the user logs in within 30 days and completes on day 31 (test with
  a shortened period in a test account).
- The Privacy and Terms pages are linked from every place listed.

---

## B5. Backups: automatic nightly server copy, plus "Download my backup" (owner's choice, 23:45)

**Owner chose:** option 1, an automatic nightly copy of the whole database and files to
low-cost private storage, and option 4, a user's own "Download my backup". Supabase Pro and
point-in-time recovery come later.

**Today:**
- the Supabase project is on the Free plan, which keeps no restorable backups for us;
- the only copy is the manual one from 15 Nov (`backups/20261115_*`).

### Part 1: nightly server backup (protects every user)
1. **New workflow** `.github/workflows/nightly-backup.yml`:
   - runs every night at **02:30 IST** (`cron: '0 21 * * *'`), and by hand from the Actions tab;
   - it must **not** be part of the deploy workflow;
   - set a `timeout-minutes` and `concurrency` like the deploy workflow.
2. **What it copies:**
   - the database: roles, schema and data, as three files with `supabase db dump`, like
     `backups/20261115_*`;
   - **every file in Storage**: the `business-media` bucket (logos, signatures, QR images).
3. **Protect it:**
   - put everything in one `simplek-backup-YYYY-MM-DD.tar.gz`;
   - **encrypt** it with `age` (or `gpg --symmetric`) using a passphrase kept only in a GitHub
     secret. Never upload anything unencrypted.
4. **Where:** a private **Cloudflare R2** bucket `simplek-backups`. The owner already uses
   Cloudflare, and the R2 free tier covers this. Upload with the S3-compatible API (`aws s3 cp
   --endpoint-url https://<account>.r2.cloudflarestorage.com`) using an R2 token that can only
   write to that bucket.
5. **How long:** keep **30 daily** copies and **12 monthly** copies (the one from the 1st of each
   month). Delete older ones in the same job, or with an R2 lifecycle rule.
6. **GitHub secrets** (never in the repo; list them in `NOTES.md` and `.env.example`):
   - `SUPABASE_DB_URL`: the direct or session connection string, not the transaction pooler;
   - `SUPABASE_SERVICE_ROLE_KEY` and `SUPABASE_URL`: for Storage;
   - `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`;
   - `BACKUP_PASSPHRASE`.
7. **If it fails:** GitHub emails the owner when a run fails. Also, a step at the end checks that
   the uploaded file exists and is larger than a minimum size.
8. **Restore guide:** write `docs/RESTORE.md`, step by step: download, decrypt, restore the
   database and files into a **new** Supabase project, then switch the app over.
9. **Test one restore** into a free test Supabase project, check the invoice counts match, and
   record the date in `docs/RESTORE.md` and `CHANGE-STATUS.md`. **Not "Done" until this test
   passes.**
10. **Privacy Notice** (B4): add "Deleted data may remain in our encrypted backups for up to 12
    months, then it is erased."

**Owner actions** (Claude Code: list them in `NOTES.md` under "Replace before launch" and walk the
owner through them):
- create the R2 bucket and token in Cloudflare;
- add the GitHub secrets;
- **store `BACKUP_PASSPHRASE` safely offline**, e.g. on paper or in a password manager. Without
  it the backups can't be opened.

### Part 2: "Download my backup" for each user
- This is the **Download my data** feature in B4: a ZIP of Excel and JSON files plus every invoice
  PDF.
- Also put a **"Download my backup"** button on the **More → Sync and backup** screen, under
  "Everything is on the server", with a line saying when the last download was made on this
  device.
- Restoring from this ZIP is **not** part of this change. Disaster recovery uses Part 1.

**Check:**
- The workflow runs by hand, and an encrypted file appears in R2.
- 31 days of files get pruned to 30 daily plus the monthly ones.
- The test restore matches the invoice counts.
- A user's backup ZIP downloads and opens on phone and web.

---

## Done checklist

- [ ] Each change committed separately (`change B1: …`). `CHANGE-STATUS.md` updated; open items in
      `NOTES.md`.
- [ ] Migrations get unique 14-digit versions and a dry run first: `deleted_at` and `deleted_by`,
      `audit_log`, totals functions, `consents`, `privacy_requests`, nominee, deletion scheduling.
      Add regression tests in `supabase/tests/`.
- [ ] `flutter analyze` clean and `flutter test` passing, plus the new money and rounding tests.
- [ ] Test plan updated: delete with Undo, the warnings, pagination, totals on a large account,
      privacy flows.
- [ ] Nightly backup running, with **one tested restore** recorded (B5).
- [ ] Tell the owner what needs a lawyer's review (Privacy Notice, Terms) and what needs his real
      details (grievance contact).
