# September 24 issue fixes

- Customer/product/service deletion archives the catalogue row (`is_active=false`). No document or document line is deleted. Archived rows remain available for historical lookups but are excluded from new-document pickers and active lists.
- Customer and product saves, deletions, and offline catalogue synchronization notify the dashboard. Out-of-order summary requests cannot replace newer results.
- Invoice Share PDF, Email, and WhatsApp PDF actions use one attachment-sharing path with sanitized filenames, Android FileProvider URI permissions, a re-entry guard, and visible failure messages.
- WhatsApp receives a best-effort recipient hint with the PDF. Its app version may still show the contact picker or omit the caption. Explicit contact-picker and message-only chat actions remain available. Nothing is sent without the user confirming inside the receiving app.
- Invoice preview uses Save & Close (the invoice was already persisted before preview). Sample preview still says Close. Both themes use the responsive share bar; WhatsApp stays on one line.
- Invoice and quotation numbers are allocated atomically per authenticated owner, document type, and April–March financial year. Fresh businesses/years begin at 01. Existing numbers are retained, not reset or renumbered.
- Optional manual numbers are checked by database unique indexes scoped to owner and financial year, case-insensitively. Duplicate failures appear as red field errors and messages. Offline manual-number saves are not queued because uniqueness cannot be verified offline.

## Database

Applied `supabase/migrations/20260924_business_document_numbers.sql` to the connected project. The migration preserves all existing business data, adds customer archival state, replaces global number uniqueness with owner/year uniqueness, and replaces all existing numbering RPC signatures.

`supabase/tests/20260924_document_regressions.sql` passed on the connected database. It verifies owner/year isolation, quotation independence, duplicate rejection, unchanged invoice records after catalogue archival, and required authentication. All fixtures and counter changes are rolled back.

## Device testing

The native share payload is covered by mocked method-channel tests. No Android device was connected during this change, so actual WhatsApp/WhatsApp Business recipient and caption behavior still requires a phone check.
