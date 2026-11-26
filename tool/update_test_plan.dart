// Rewrites the text of chosen cells on the 'Test Cases' sheet of
// docs/Simplek_Test_Plan.xlsx, leaving every other part of the file (formulas,
// styles, other sheets) byte-for-byte unchanged.
// Run: dart run tool/update_test_plan.dart
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

const _sheet = 'xl/worksheets/sheet3.xml';

const _updates = <String, String>{
  // ONB-001 and ONB-006: updated again for CR-25 at the end of this list.
  // ONB-008: the financial year field was removed.
  'F32': 'No Financial year field (removed 19 Nov 2026)',
  'H32':
      '1. Look for a Financial year field in onboarding step 1.\n'
      '2. Look for it in Business Settings.',
  'I32': '-',
  'J32':
      'There is no Financial year field in either place. Document numbers '
      'take the year from the document date (see INV-013).',
  // ONB-011: logo crop editor.
  'F35': 'Upload, crop and rotate a logo',
  'H35':
      "1. Tap the Logo tile, then 'Upload a photo'.\n"
      '2. Drag the corners and edges to crop, pinch or scroll to zoom, try '
      "'Square' and rotate left/right.\n"
      "3. Tap Next, then 'Use this logo'.\n"
      "4. Tap the tile again, then 'Edit / crop', change it and save.",
  'I35': 'A JPG/PNG logo, also try a 5 MB phone photo',
  'J35':
      'The editor opens full screen; crop, zoom, rotate and Reset work. The '
      'logo tile shows the result. A large photo is accepted without '
      'freezing. Cancel leaves the logo unchanged.',
  // ONB-012: signature editor and actions.
  'F36': 'Draw, upload, crop, edit and remove the signature',
  'H36':
      "1. Tap the Signature tile, then 'Draw it'; sign and tap 'Use signature'.\n"
      "2. Tap the tile, then 'Upload a new one'; choose a phone photo of a "
      "signature on paper; keep 'Signature shape'; tap Next.\n"
      "3. Keep 'Clean background' on and move Strength.\n"
      "4. Check the 'On the invoice' preview and tap 'Use this signature'.\n"
      "5. Tap the tile, then 'Remove'.",
  'J36':
      'Clean background leaves only the ink (the paper shows as the chequered '
      "pattern). The 'On the invoice' box shows 'For BUSINESS NAME', the "
      "signature centred above the line, and 'Authorised signatory'. After "
      'Remove the tile is empty and PDFs show an empty signature box with the '
      'line.',
  // NAV-008: More page no longer has theme or fingerprint controls.
  'J49':
      'More shows the business card, Tools (Quotations, Payments, Reports, '
      'Search everything, Accountant access, Sync & backup) and Log out only. '
      'No theme or fingerprint controls: they are at the bottom of Settings '
      'under App preferences. Each item opens the right screen.',
  // INV-020: tidy list rows, tap opens the Invoice view.
  'J110':
      "Each row shows the customer name, 'number • dd/mm/yyyy', the amount "
      'with Indian commas (e.g. ₹10,600.21) and a coloured status chip. '
      "Tapping a row, or ⋮ then 'Preview', opens the Invoice view: Share PDF, "
      'WhatsApp, Email, Print (and Download on web), More with Edit, '
      'Duplicate and Record payment, and Total, Paid, Balance due and Due '
      'date.',
  // DOC-001: updated again for CR-25 at the end of this list.
  // DOC-004: signature placement.
  'J130':
      "The signature appears on invoices and quotations in the 'For BUSINESS "
      "NAME' box, centred above the line at a readable size: not stretched, "
      'cut off or pushed to one side.',
  // DOC-014: quotation layout.
  'J140':
      'PDF titled QUOTATION with Quotation no., Quotation date, Valid until, '
      'items, taxes, Round off, terms, bank details (no UPI QR) and signature. '
      'Sharing works as for invoices.',
  // DOC-015: the rupee sign now prints.
  'J141':
      '₹ prints on every amount. Record whether Hindi or Kannada names print '
      'correctly; complex scripts are a known limitation of the PDF library.',
  // DOC-016: sample preview.
  'J142':
      "'Sample invoice format' shows the new layout with sample data and "
      "'SAMPLE – not a real document' under the title; print/share are not "
      "available; 'Close' returns.",
  // CR-25 (25 Nov 2026): onboarding with GST Yes/No and the split address.
  'H25':
      "1. Business details: tap 'Yes, registered', choose the type, type the "
      "GSTIN and tap 'Verify GSTIN'. Fill PIN code, address line 1, city and "
      'District (State fills from the GSTIN, read-only).\n'
      '2. Fill Terms and conditions.\n'
      '3. Fill Branding and payments.\n'
      "4. Tap 'Finish setup'.",
  'I25':
      'Real GSTIN provided by owner (see Read Me), PIN 577201, '
      'Invoice prefix: TINV, Quotation prefix: TQTN',
  'H26':
      "1. Leave the GST question unanswered and tap Next: 'Select Yes or No' "
      'shows.\n'
      "2. Tap 'No, not registered'.\n"
      '3. Fill the address: PIN, line 1, city, then State and District.\n'
      '4. Complete all steps.',
  'I26': 'State: Kerala, a district of Kerala, PIN 682001',
  'J26':
      'No GSTIN, registration type or place of supply fields. State and '
      'District are required. Setup completes without a GSTIN. A new invoice '
      'has no Place of supply and its PDF says INVOICE.',
  'I27': '29ABCDE1234F1ZW (correct format and check digit, not registered)',
  'J29':
      "'A GSTIN has 15 characters' for a short one; 'This GSTIN fails its check "
      "digit' for 29ABCDE1234F1Z5. No lookup is made.",
  'H30':
      '1. Leave Your name, Business name, PIN code, Address line 1, City, '
      'State and District empty.\n'
      '2. Tap Next.\n'
      '3. Type PIN 077201.',
  'I30': 'PIN: 077201',
  'J30':
      "Each empty required field shows its own error under it (e.g. 'Enter the "
      "PIN code', 'Select the state'). 077201 shows 'Enter a 6-digit PIN code "
      "that does not start with 0'. No 'Default place of supply' or "
      "'Financial year'.",
  'J31':
      "Typing abcde1234f shows ABCDE1234F (on web too). It can't go past 10 "
      "characters; spaces and symbols can't be typed. ABCDE12345 shows 'Enter "
      "a valid PAN'.",
  'J98':
      "'Place of supply is required', 'This GSTIN fails its check digit' (or "
      "'Enter a valid GSTIN'), 'Choose a product or service', 'Enter a rate "
      "from 0 to 100', 'Enter valid ...'. Nothing saved.",
  'J127':
      'A border on every page; logo with business name, the address on at '
      'most two lines, GSTIN (registered only) and Email · Mobile; no '
      "'State: … (code)' line; TAX INVOICE (GST registered) or INVOICE (not "
      'registered); Bill to / invoice details box with Place of supply (GST '
      'only); items with HSN/SAC (GST only), Qty, Rate, GST %, Amount, no SKU; '
      'Amount in words; totals; bank and UPI box (QR and text aligned at the '
      'top, UPI ID on one line, no taller than the bank details); the '
      'Description box when filled; terms and signature. An 8-item invoice '
      'with a 300-character description fits on one page.',
};

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

void main() {
  final file = File('docs/Simplek_Test_Plan.xlsx');
  final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
  final output = Archive();
  var changed = 0;
  for (final entry in archive.files) {
    if (entry.name != _sheet) {
      output.addFile(entry);
      continue;
    }
    var xml = utf8.decode(entry.content as List<int>);
    for (final MapEntry(key: cell, value: text) in _updates.entries) {
      final pattern = RegExp(
        '(<c r="$cell"[^>]*t="inlineStr"[^>]*><is><t)([^>]*)(>)(.*?)(</t></is></c>)',
        dotAll: true,
      );
      final match = pattern.firstMatch(xml);
      if (match == null) {
        stderr.writeln('Cell $cell not found as inline text; left unchanged.');
        continue;
      }
      final replacement =
          '${match[1]} xml:space="preserve">${_escape(text)}${match[5]}';
      xml = xml.replaceRange(match.start, match.end, replacement);
      changed++;
    }
    final bytes = utf8.encode(xml);
    output.addFile(ArchiveFile(entry.name, bytes.length, bytes));
  }
  file.writeAsBytesSync(ZipEncoder().encode(output));
  stdout.writeln('Updated $changed of ${_updates.length} cells.');
}
