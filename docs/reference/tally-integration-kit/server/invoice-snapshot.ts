export interface AddressSnapshot {
  name: string;
  label?: string;
  line1: string;
  line2?: string | null;
  city: string;
  district: string;
  state: string;
  pincode: string;
  mobile: string;
  email?: string | null;
}
export interface InvoiceSnapshot {
  invoiceNumber: string;
  orderNumber: string;
  issuedAt: string;
  placeOfSupply: string;
  intraState: boolean;
  seller: {
    name: string;
    address: string;
    pincode: string;
    phones: string[];
    email: string;
    website: string;
    gstin: string;
    pan: string;
    state: string;
    logoPath: string;
    signaturePath: string;
    /** Change 05.76 (older invoices may lack these): the name, address and contact printed as the seller. */
    legalName?: string;
    gstAddress?: string;
    customerCare?: string;
  };
  buyer: {
    name: string;
    address: string;
    mobile: string;
    email: string | null;
    gstin: string | null;
    businessName: string | null;
    state: string;
  };
  items: {
    name: string;
    packSize: string;
    hsnCode: string;
    quantity: number;
    unitGrossPaise: number;
    ratePaise: number;
    /** Change 05.22 (older invoices have none). */
    bulkDiscountPaise?: number;
    discountPaise: number;
    taxablePaise: number;
    gstPercent: number;
    cgstPaise: number;
    sgstPaise: number;
    igstPaise: number;
    totalPaise: number;
  }[];
  totals: {
    subtotalPaise: number;
    /** Change 05.22: "Bulk discount (10%)", above the coupon line (older invoices have none). */
    bulkDiscountPaise?: number;
    bulkDiscountPercent?: number;
    discountPaise: number;
    /** "Discount (10%)" for a percentage discount on an offline invoice (change 03.22). */
    discountLabel?: string;
    /** Change 07.3: a rupee discount as typed, off the price including GST (older invoices have none). */
    discountEnteredPaise?: number;
    taxablePaise: number;
    cgstPaise: number;
    sgstPaise: number;
    igstPaise: number;
    taxPaise: number;
    shippingPaise: number;
    roundOffPaise: number;
    totalPaise: number;
  };
  bank: { bankName: string; branch: string; accountNumber: string; ifsc: string; accountName: string };
  upiId: string;
  qrImagePath: string;
  terms: string;
  palette: string;
}
