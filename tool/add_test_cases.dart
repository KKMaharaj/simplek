// Adds the CR-25B test cases to the 'Test Cases' sheet of
// docs/Simplek_Test_Plan.xlsx, styled like the rows above them, and widens
// every range and formula that ends at the old last row (the Summary
// counts, the Bug Log look-ups, filters and drop-downs) to the new last row.
// Also marks Known Issues KI-01 and KI-02 as fixed. Other parts of the file
// are left byte-for-byte unchanged. Running it twice adds nothing twice.
// Run: dart run tool/add_test_cases.dart
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

const _cases = 'xl/worksheets/sheet3.xml';
const _knownIssues = 'xl/worksheets/sheet5.xml';

/// ID, module, feature, platform, priority, title, preconditions, steps,
/// test data, expected result.
const _rows = <List<String>>[
  [
    'INV-026',
    'Invoices',
    'Delete',
    'Both',
    'High',
    'Delete an invoice (GST business), then Undo',
    'GST-registered business; an invoice already in a report',
    "1. Open the invoice; tap ⋯ → 'Delete invoice'.\n"
        '2. Read the warning; tap Delete.\n'
        '3. Check Invoices, Home, Reports and GSTR-1.\n'
        "4. Tap 'Undo' in the message within 10 seconds.",
    'Invoice INV/2026-27/24',
    "The warning reads 'Delete invoice INV/2026-27/24?', 'It will be removed "
        "from your invoices, totals and reports.' and the highlighted GST line "
        "about GSTR-1 differences, with Cancel and Delete. After Delete the "
        'invoice is gone from the list, Home totals, Reports and GSTR-1. Undo '
        'brings it back with its payments.',
  ],
  [
    'INV-027',
    'Invoices',
    'Delete',
    'Both',
    'High',
    'Delete warning without GST',
    'Business not registered under GST',
    "1. In the Invoices list, tap a row's ⋮ → 'Delete invoice'.",
    '-',
    'The same warning without the GST line. After Delete the list and totals '
        'update.',
  ],
  [
    'INV-028',
    'Invoices',
    'Delete',
    'Both',
    'High',
    'A deleted invoice number is never reused',
    'Delete the newest invoice (e.g. …/25)',
    '1. Create a new invoice and save it.',
    '-',
    'The new invoice gets the next number (…/26), not the deleted one.',
  ],
  [
    'INV-029',
    'Invoices',
    'Edit warning',
    'Both',
    'Medium',
    'Editing an older invoice warns once (GST only)',
    'GST business; an invoice dated before today',
    "1. Open the invoice → ⋯ → 'Edit invoice'.\n"
        '2. Change a line and save.\n'
        "3. Edit today's invoice; then switch GST off and edit the old one.",
    '-',
    "'Changes to this invoice may cause differences in GST returns you've "
        "already filed.' with Cancel and 'Edit anyway', once per edit, not "
        "while typing. No warning for today's invoice or a business without "
        'GST.',
  ],
  [
    'INV-030',
    'Invoices',
    'Delete',
    'Both',
    'High',
    'An accountant cannot delete',
    'Accountant viewing a shared business',
    '1. Open an invoice and its ⋯ menu, and a row ⋮ menu.',
    '-',
    "No 'Delete invoice' anywhere; the server refuses it too.",
  ],
  [
    'SET-009',
    'Business settings',
    'Old invoices',
    'Both',
    'Medium',
    'Note after changing details old invoices show',
    'Saved business profile',
    '1. Change the business name (or address, GSTIN, bank, UPI) and save.\n'
        "2. Change only the owner's name and save.\n"
        "3. Edit a product's GST rate or HSN/SAC and save.",
    '-',
    "Steps 1 and 3: 'Old invoices will also show the new details when you "
        "open or share them again.' (GST businesses add '…which may not match "
        "GST returns you've already filed.'). Step 2: just 'saved'.",
  ],
  [
    'GST-012',
    'GST calculations',
    'Rounding',
    'Both',
    'High',
    'CGST + SGST always equal the tax',
    'Customer in your state',
    '1. New invoice: 1 × ₹101 at 5%.\n2. Check the totals and the PDF.',
    '₹101, 5%',
    'Tax ₹5.05 = CGST ₹2.53 + SGST ₹2.52 (never 2.53 + 2.53). Total payable '
        '₹106, Round off − ₹0.05; the PDF shows the same figures.',
  ],
  [
    'GST-013',
    'GST calculations',
    'Rounding',
    'Both',
    'High',
    'Rounding to the paisa: 3 × ₹33.33 at 18%',
    '-',
    '1. New invoice: 3 × ₹33.33 at 18%.',
    '3 × ₹33.33, 18%',
    'Taxable ₹99.99, tax ₹18.00 (CGST ₹9.00 + SGST ₹9.00), total ₹118, '
        'Round off + ₹0.01. Saving succeeds.',
  ],
  [
    'GST-014',
    'GST calculations',
    'Rounding',
    'Both',
    'Medium',
    'Mixed rates and a ₹1.25 crore invoice',
    '-',
    '1. Invoice with lines at 0%, 5%, 12% and 18%; check the PDF tax lines.\n'
        '2. Invoice: 2.5 × ₹50,00,000.40 at 18%.',
    '-',
    "The PDF's CGST/SGST per rate add up to the invoice's CGST/SGST. The big "
        'invoice shows ₹1,47,50,001.00 and saves.',
  ],
  [
    'RPT-012',
    'Reports & exports',
    'Totals',
    'Both',
    'High',
    'Totals cover all invoices (600+)',
    'A test account with 600+ invoices',
    '1. Compare Home (sales, to collect, collected) and Reports with a direct '
        'SQL sum.',
    'SQL: sum(total_amount) etc. of non-draft, non-cancelled, not deleted',
    'Every total equals the SQL sum. Drafts, cancelled and deleted invoices '
        'are left out.',
  ],
  [
    'RPT-013',
    'Reports & exports',
    'Dates',
    'Both',
    'Medium',
    'Date presets on Invoices and Reports',
    '-',
    '1. Pick Today, Last 7 days, This month, This quarter, This year, Custom.',
    '-',
    'The button shows the preset and dates; This quarter and This year follow '
        'the financial year (Apr–Mar). Totals and lists change to match; ✕ '
        'goes back to all dates.',
  ],
  [
    'RPT-014',
    'Reports & exports',
    'Exports',
    'Both',
    'High',
    'Exports contain every matching invoice',
    '600+ invoices; a date preset chosen',
    '1. Export PDF, Excel, CSV and Tally.\n2. Count the rows.',
    '-',
    'Each file has all invoices in the dates (not 100 or 500), with the '
        'business, the dates, the count and the time made at the top.',
  ],
  [
    'NAV-012',
    'Home & navigation',
    'Pages',
    'Web',
    'High',
    'Numbered pages from 600 px',
    '100+ invoices; web at 1280 px',
    '1. Open Invoices; go to page 2, then the last page.\n'
        '2. Change Rows to 50; reload; log out and in.',
    '-',
    "'Showing 26–50 of 287', ‹ Prev 1 2 3 … 12 Next ›. The rows choice "
        '(10/25/50/100) is remembered for the user. Same on Quotations, '
        'Customers, Items.',
  ],
  [
    'NAV-013',
    'Home & navigation',
    'Pages',
    'Android',
    'High',
    'Phones load pages as you scroll',
    '100+ invoices; phone',
    '1. Open Invoices and scroll down.',
    '-',
    "The header shows '287 invoices · Page 2 of 12' as more load, 25 at a "
        'time, without jumps.',
  ],
  [
    'NAV-014',
    'Home & navigation',
    'Web address',
    'Web',
    'Medium',
    'Page, filters and sort are kept in the address',
    'Web',
    '1. Invoices: filter Unpaid, sort by amount, This month, page 3.\n'
        '2. Reload. 3. Open an invoice and press Back.',
    '-',
    'The address shows ?tab=invoices&page=3&status=unpaid&sort=amount&period='
        'this_month; reload and Back return to the same view.',
  ],
  [
    'SRCH-005',
    'Search',
    'All data',
    'Both',
    'High',
    'Search finds old records',
    '600+ invoices',
    '1. In Invoices, search a number from page 20.\n'
        '2. Search the same in Search everything.',
    '-',
    'Both find it (search runs on the server); a filter change goes back to '
        'page 1.',
  ],
  [
    'AUTH-017',
    'Sign up & login',
    'Consent',
    'Both',
    'High',
    'Sign-up needs the consent tick',
    'New email',
    '1. Fill the sign-up form without ticking the box; tap Send.\n'
        '2. Tick it; open the Privacy Notice and Terms links; send.',
    '-',
    "Step 1: 'Tick the box to create your account'. The box starts unticked. "
        'After signing up, a consents row exists (time, version, web/Android, '
        'IP).',
  ],
  [
    'AUTH-018',
    'Sign up & login',
    'Consent',
    'Both',
    'Medium',
    'Existing users accept the updated notice once',
    'An account created before 27 Nov 2026',
    '1. Log in.\n2. Accept.\n3. Log out and in again.',
    '-',
    "'We've updated our Privacy Notice' needs the tick and Accept; Log out "
        'is offered. It does not show again.',
  ],
  [
    'SEC-007',
    'Security & data isolation',
    'Privacy pages',
    'Both',
    'High',
    'Privacy Notice and Terms are linked everywhere',
    '-',
    '1. Check the website footer, sign-up, login and Settings.',
    '-',
    'Each opens /privacy or /terms; both show the version and date and the '
        'grievance contact.',
  ],
  [
    'SEC-008',
    'Security & data isolation',
    'Download my data',
    'Both',
    'High',
    'Download my data',
    'Account with invoices, a deleted invoice and payments',
    '1. Settings → Your data and privacy → Download my data.\n'
        '2. Open the ZIP.',
    '-',
    'The ZIP opens: simplek-data.json and .xlsx with matching counts, and '
        'every invoice as a PDF (deleted ones in invoices/deleted). The link '
        'works for 24 hours.',
  ],
  [
    'SEC-009',
    'Security & data isolation',
    'Delete account',
    'Both',
    'High',
    'Delete my account: grace period and cancel',
    'Test account only',
    '1. Delete my account; type the business name.\n'
        '2. Log in again within 30 days.\n'
        '3. Delete again and test day 31 with a shortened period (SQL test).',
    '-',
    'The button works only when the name matches; you are logged out '
        'everywhere. Logging in cancels it with a message. On day 31 all data '
        'and the login are deleted.',
  ],
  [
    'SEC-010',
    'Security & data isolation',
    'Rights',
    'Both',
    'Medium',
    'Nominee and Raise a concern',
    '-',
    '1. Nominate a person; edit; remove.\n2. Raise a concern.',
    '-',
    "The nominee shows on the page. The concern shows 'Open' with a reply-by "
        'date 30 days ahead; it cannot be changed by the user.',
  ],
  [
    'SEC-011',
    'Security & data isolation',
    'Storage notice',
    'Web',
    'Low',
    'Web storage notice on first visit',
    'A new browser profile',
    "1. Open the web app.\n2. Tap OK; reload.",
    '-',
    'A small bar says only essential storage is used, with Privacy Notice and '
        'OK; it does not come back after OK.',
  ],
  [
    'SYNC-008',
    'Live sync, offline & backup',
    'User backup',
    'Both',
    'Medium',
    'Download my backup',
    '-',
    '1. More → Sync and backup → Download my backup.',
    '-',
    "Under 'Everything is on the server', the ZIP downloads and the card "
        'shows when it was last downloaded on this device.',
  ],
  [
    'SYNC-009',
    'Live sync, offline & backup',
    'Nightly backup',
    'Web',
    'High',
    'Nightly backup reaches R2',
    "Owner's R2 bucket and GitHub secrets set",
    "1. GitHub → Actions → 'Nightly backup' → Run workflow.\n"
        '2. Check R2 simplek-backups/daily.',
    '-',
    'The run passes; an encrypted simplek-backup-YYYY-MM-DD.tar.gz.gpg is in '
        'daily/ (and monthly/ on the 1st). With 31 daily files, the oldest is '
        'removed.',
  ],
  [
    'SYNC-010',
    'Live sync, offline & backup',
    'Restore',
    'Web',
    'High',
    'Test restore matches the counts',
    'A test Supabase project',
    '1. Follow docs/RESTORE.md with the latest backup.\n'
        '2. Compare the counts with MANIFEST.txt.',
    '-',
    'Every count matches; record the date in docs/RESTORE.md.',
  ],
  [
    'SEC-012',
    'Security & data isolation',
    'Audit log',
    'Both',
    'Medium',
    'Deletes and edits are logged',
    '-',
    '1. Edit, delete and restore an invoice.\n'
        '2. In Supabase, look at audit_log.',
    '-',
    "Three rows (edit, delete, restore) with who, when and the invoice's old "
        'values; the app cannot read the log.',
  ],
];

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _cell(String ref, int style, String text) => text.isEmpty
    ? '<c r="$ref" s="$style" t="inlineStr"></c>'
    : '<c r="$ref" s="$style" t="inlineStr"><is><t xml:space="preserve">'
          '${_escape(text)}</t></is></c>';

String _row(int number, List<String> values) {
  final cells = StringBuffer();
  const letters = 'ABCDEFGHIJ';
  for (var i = 0; i < 10; i++) {
    cells.write(_cell('${letters[i]}$number', i == 0 ? 23 : 24, values[i]));
  }
  cells
    ..write(_cell('K$number', 25, ''))
    ..write(_cell('L$number', 25, 'Not Run'));
  for (final column in 'MNOP'.split('')) {
    cells.write(_cell('$column$number', 25, ''));
  }
  cells
    ..write('<c r="Q$number" s="26" t="n"></c>')
    ..write(_cell('R$number', 25, ''))
    ..write(_cell('S$number', 25, ''));
  final lines = values
      .map((v) => '\n'.allMatches(v).length + 1)
      .fold(1, (a, b) => a > b ? a : b);
  final height = (lines * 15 + 30).clamp(54, 120);
  return '<row r="$number" ht="$height" customHeight="1">$cells</row>';
}

void main() {
  final file = File('docs/Simplek_Test_Plan.xlsx');
  final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
  final cases = utf8.decode(archive.findFile(_cases)!.content as List<int>);
  if (cases.contains('<t xml:space="preserve">${_rows.first.first}</t>') ||
      cases.contains('<t>${_rows.first.first}</t>')) {
    stdout.writeln('Already added.');
    return;
  }
  final lastRow = RegExp(r'<row r="(\d+)"')
      .allMatches(cases)
      .map((m) => int.parse(m[1]!))
      .reduce((a, b) => a > b ? a : b);
  final newLast = lastRow + _rows.length;
  String widen(String xml) => xml
      .replaceAll('\$$lastRow', '\$$newLast')
      .replaceAllMapped(
        RegExp('([A-Z]+)(\\d+):([A-Z]+)$lastRow(?=["\\s])'),
        (m) => '${m[1]}${m[2]}:${m[3]}$newLast',
      );
  final output = Archive();
  for (final entry in archive.files) {
    if (!entry.name.startsWith('xl/worksheets/sheet')) {
      output.addFile(entry);
      continue;
    }
    var xml = utf8.decode(entry.content as List<int>);
    if (entry.name == _cases) {
      final rows = [
        for (final (index, values) in _rows.indexed)
          _row(lastRow + 1 + index, values),
      ].join();
      xml = xml.replaceFirst('</sheetData>', '$rows</sheetData>');
    }
    if (entry.name == _knownIssues) {
      xml = xml
          .replaceFirst(
            'Home totals add up only the newest 100 invoices.',
            'Fixed on 27 Nov 2026 (CR-25B B2): Home totals now cover all '
                'invoices (was: only the newest 100).',
          )
          .replaceFirst(
            'Reports and GSTR-1 load only the newest 500 invoices / 5,000 line '
                'items, so older periods can be incomplete.',
            'Fixed on 27 Nov 2026 (CR-25B B2): Reports, GSTR-1 and exports '
                'now cover all invoices (was: the newest 500).',
          );
    }
    xml = widen(xml);
    final bytes = utf8.encode(xml);
    output.addFile(ArchiveFile(entry.name, bytes.length, bytes));
  }
  file.writeAsBytesSync(ZipEncoder().encode(output));
  stdout.writeln(
    'Added ${_rows.length} test cases (rows ${lastRow + 1}–$newLast); '
    'ranges now end at row $newLast.',
  );
}
