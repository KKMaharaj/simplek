# Simplek Design Specification & Implementation Handoff (DESIGN_PROPOSAL.md)
*Prepared for Flutter Engineering Team & Codex AI Integration*

---

## 1. Executive Summary & Design Philosophy

**Simplek** ("Invoicing made easy") has been redesigned as an executive, high-trust Indian billing solution. Moving away from utilitarian generic dashboards, this design introduces:
- **Restrained Premium Palette**: Deep Executive Indigo (`#1E3A8A` / `#2563EB`) as primary, supported by rich slate grays. Financial health indicators use calm Emerald (`#059669`), subtle Amber (`#D97706`), and muted Crimson (`#DC2626`).
- **Dual Theme Support (Light & Dark)**: Full tokens specified for both modes with high WCAG AAA contrast and zero eye fatigue for nighttime ledger work.
- **Workflow Speed**: Modernized navigation with persistent quick-action sheet, inline customer GSTIN verification popup (2-second auto-dismiss with preserved form state), and direct auto-selection of newly created items/customers into builders.
- **Strict Compliance with DESIGN.md**: Preserves Flutter M3 foundations, 48px touch targets, full 36-state Indian States/UT selector, UPI QR placement, and unchanged invoice/quotation legal terms.

---

## 2. Design Tokens & Theme Matrix (Codex / Flutter Dart Ready)

```dart
// simplek_theme_tokens.dart
import 'package:flutter/material.dart';

class SimplekColors {
  // Brand Core
  static const Color primaryLight = Color(0xFF1E3A8A); // Deep Executive Indigo
  static const Color primaryVariantLight = Color(0xFF2563EB); // Vibrant Royal Blue
  static const Color primaryDark = Color(0xFF60A5FA); // Soft Blue for Dark Mode
  static const Color primaryContainerDark = Color(0xFF1E293B);

  // Background & Surfaces (Light)
  static const Color bgLight = Color(0xFFF8FAFC); // Slate-50 off-white
  static const Color surfaceLight = Color(0xFFFFFFFF); // Pure White cards
  static const Color surfaceSubtleLight = Color(0xFFF1F5F9);
  static const Color borderLight = Color(0xFFE2E8F0); // 1px crisp outline

  // Background & Surfaces (Dark)
  static const Color bgDark = Color(0xFF0B0F19); // Midnight Obsidian
  static const Color surfaceDark = Color(0xFF161F30); // Deep Slate Navy container
  static const Color surfaceSubtleDark = Color(0xFF1E293B);
  static const Color borderDark = Color(0xFF283548); // Subtle dark outline

  // Financial Status Semantics
  static const Color statusPaidLight = Color(0xFF059669); // Forest Emerald
  static const Color statusPaidBgLight = Color(0xFFECFDF5);
  static const Color statusPaidDark = Color(0xFF34D399);
  static const Color statusPaidBgDark = Color(0xFF064E3B);

  static const Color statusPendingLight = Color(0xFFD97706); // Warm Amber
  static const Color statusPendingBgLight = Color(0xFFFFFBEB);
  static const Color statusPendingDark = Color(0xFFFBBF24);
  static const Color statusPendingBgDark = Color(0xFF78350F);

  static const Color statusOverdueLight = Color(0xFFDC2626); // Crimson
  static const Color statusOverdueBgLight = Color(0xFFFEF2F2);
  static const Color statusOverdueDark = Color(0xFFF87171);
  static const Color statusOverdueBgDark = Color(0xFF7F1D1D);

  // Typography
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textMutedLight = Color(0xFF64748B);
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textMutedDark = Color(0xFF94A3B8);
}

class SimplekDimensions {
  static const double radiusInput = 12.0;
  static const double radiusCard = 16.0;
  static const double radiusButton = 12.0;
  static const double minTouchTarget = 48.0;
  static const double gutter = 16.0;
}
```

---

## 3. Screen Hierarchy & Architecture

```
App Root
├── [1] Splash & Auth (2.6s branded entry, phone/email OTP, clean validation)
├── [2] Main Navigation Shell
│   ├── Bottom Bar: Dashboard (Home) | Invoices | Customers | Products | More (Settings/Reports)
│   └── Global Action: Floating Speed Dial (+) -> New Invoice | New Quotation | Record Payment
├── [3] Dashboard
│   ├── Top Bar: "Simplek" full brand mark + Search + Notifications/Sync + Profile
│   ├── KPI Financial Carousel (Total Sales, Total Outstanding, Invoices Count, Customers)
│   ├── Quick Action Bar (4 minimal pill chips)
│   ├── Recent Invoices List (Status badges, amount in ₹ Indian format, click-to-preview)
│   └── Empty / Offline Banner Indicator
├── [4] Invoice & Quotation Builder (Flow Contract)
│   ├── 1. Customer Selector (Auto Place of Supply, instant "Add New" inline sheet)
│   ├── 2. Document Meta (Invoice No, Dates, Due Date)
│   ├── 3. Line Items Table (Add Item, Qty, Rate, GST %, Auto-calc line totals)
│   ├── 4. Tax Breakdown (Subtotal, CGST/SGST or IGST based on State match)
│   ├── 5. Fixed Terms Accordion (Pre-filled non-destructive defaults)
│   └── 6. Dual Sticky Footer: [Save & Close] (Secondary) | [Save & Next] (Primary)
├── [5] Customer Editor (GST Yes/No Logic)
│   ├── Registered Toggle -> GSTIN field with [Verify] button
│   ├── 2.0-second Floating Verification Toast (auto-fills trade name, state, address)
│   └── State Selector (Complete 36 Indian States & UTs searchable modal)
└── [6] Document Preview & Sharing (A4 Canvas)
    ├── PDF Preview Viewport
    ├── Top Action: [Close] back to dashboard
    ├── Sticky Primary CTA: [Save & Add New Invoice]
    └── Action Grid: WhatsApp (with PDF attachment) | Email | Print | Share PDF
```

---

## 4. Key UX Flow Innovations for Flutter Developers

### A. Customer Editor GST Verification Logic
- When user switches GST to **Yes**, GSTIN appears with auto-uppercase and regex validation (`^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$`).
- On tap of **Verify**, a discreet non-blocking HUD appears atop the sheet. On success (or failure), it displays verified legal name and auto-populates Trade Name, Address, and State.
- Toast self-dismisses after 2,000 ms, leaving focus on any remaining optional inputs.

### B. Builder Inline Entity Creation
- Selecting "+ New Customer" inside the Invoice Builder opens the Customer Sheet above the builder without unloading form state.
- Upon saving, the builder directly receives the returned model and selects it immediately, updating the Place of Supply automatically.

### C. Save Actions Contract
- **Save & Close**: Validates payload -> Writes to Supabase/local cache -> Pops back to Dashboard with a subtle success snackbar.
- **Save & Next**: Validates payload -> Transitions directly to `InvoicePreviewScreen` with generated PDF byte stream.
