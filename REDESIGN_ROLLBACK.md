# Modern design and undo

## Switch back inside the app

Open **More → Business Profile & Settings → App design → Classic — previous design**.
The dashboard also has a Settings icon. Switch to **Modern** again whenever you want.
Your choice persists across launches. This changes the presentation, not your customers,
products, documents, payments, GST settings, custom terms, or account.
Light / Dark / System default remains a separate preference in either design.

## Source-code safety checkpoint

- Previous working application: commit `3e1aae2` on `master`.
- Redesign work: branch `codex/ui-redesign`.
- Ask the developer to revert the redesign if you want a complete code rollback.
- Do not reset the database or uninstall the app to undo the design.
- Do not use a hard Git reset if newer work exists. Review the diff and revert only the redesign commits.

## Implementation scope

Modern theme tokens, dashboard, bottom navigation, quick-create sheet, searchable state
selectors, sticky document save actions, collapsible editable terms, responsive sharing
actions, and an in-app Classic design fallback. Authentication and tax/save calculations
are unchanged. Quotation Email/WhatsApp attachment parity remains a separate known gap;
this UI work does not pretend to fix it. Use Share PDF to export a quotation file.

The palette follows the supplied proposal; its claims of AAA compliance and “zero eye
fatigue” are not adopted as verified results. Test real-device accessibility and readability.
