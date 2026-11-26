# Personal data breach response plan (CR-25B B4.8)

What to do if personal data in Simplek is, or may have been, lost, seen by
someone who should not see it, changed or made unavailable. It follows the
DPDP Act 2023 and DPDP Rules 2025: inform affected users **without delay**
and report to the **Data Protection Board of India within 72 hours** of
becoming aware.

*Names and contacts below are placeholders until the owner fills them in
(`NOTES.md`, "Replace before launch").*

## Who does what

| Role | Person | Does |
|---|---|---|
| Breach lead | [Owner, to be added] | Decides, informs users and the Board, signs off |
| Technical lead | [Developer, to be added] | Contains, investigates, fixes, keeps the evidence |
| Grievance contact | [Grievance contact, to be added] | Answers affected users' questions |

Keep a written log from the first minute: what was seen, when, by whom, and
every step taken.

## 1. Contain (first hours)

- Stop the leak: revoke the exposed key or token (Supabase → Project
  Settings → API keys; Cloudflare R2 token; GitHub secrets), sign the
  affected users out (Supabase Auth), turn off the affected feature or
  function, or put the site in maintenance by redeploying an earlier
  version in Cloudflare Pages.
- Do **not** delete logs, rows or files: they are evidence. Take a fresh
  backup (`backups/`, or run the nightly backup workflow by hand).

## 2. Assess (within 24 hours)

- What data: account data, business profiles, customers' data, invoices,
  payments, files?
- Whose and how many: list the affected accounts (and, for customer data,
  the businesses whose customers are affected).
- How it happened, since when, and whether it is still happening.
- The likely harm to the people affected.

## 3. Inform affected users (without delay)

Email each affected account owner (and, where their customers' data is
affected, help the business inform its customers, as the business is the
Data Fiduciary for that data). Say in plain language:

- what happened and when, and what data of theirs was affected;
- the likely consequences;
- what we have done and are doing about it;
- what they can do to protect themselves (for example change their
  password, watch for fraud);
- who to contact: the grievance contact above.

## 4. Report to the Data Protection Board of India (within 72 hours)

Report through the Board's process with: the nature and extent of the
breach, when and how it happened, the likely impact, the people affected,
what was done to contain it and reduce harm, and the steps to stop it
happening again. Send any update the Board asks for, and a full report as
the Rules require.

## 5. Fix and learn

- Fix the cause, test it, and deploy.
- Write a short report: timeline, cause, impact, what changed. Update
  `docs/SECURITY.md` if a safeguard changed.
- Review this plan.
