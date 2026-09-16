class DocumentDefaults {
  static const legacyQuotation =
      '1. This quotation is valid for 30 days from the date of issue.\n'
      '2. Prices and availability are subject to confirmation.\n'
      '3. Taxes will be charged as applicable.\n'
      '4. Work or supply begins after written acceptance.';
  static const legacyInvoice =
      '1. Payment is due by the due date shown on the invoice.\n'
      '2. Please mention the invoice number with every payment.\n'
      '3. Goods once sold will not be returned unless agreed in writing.\n'
      '4. Subject to local jurisdiction.';
  static const quotation =
      '1. This quotation is valid for 30 days from the date of issue.\n'
      '2. Prices and availability are subject to confirmation.\n'
      '3. Taxes will be charged as applicable.\n'
      '4. Work or supply begins after accepting the quotation by making advance payment';
  static const invoice =
      '1. Payment is due by the due date shown on the invoice.\n'
      '2. 18% p.a Interest will be charged on the invoice amount if the amount is not paid within due date.\n'
      '3. No reduction in the invoice amount will be entertained.\n'
      '4. Subject to local jurisdiction.';

  static String resolve(String? saved, {required bool isQuotation}) {
    final value = saved?.trim() ?? '';
    final legacy = isQuotation ? legacyQuotation : legacyInvoice;
    return value.isEmpty || value == legacy
        ? (isQuotation ? quotation : invoice)
        : saved!;
  }
}
