-- Change 07.3: every voucher sent to Tally, by its stable GUID, so the export
-- screen can show "already exported on [date]" and a second import updates the
-- voucher instead of creating a second one. Additive and safe on the live database.
CREATE TABLE "TallyExport" (
    "guid" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "number" TEXT NOT NULL,
    "firstExportedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastExportedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "count" INTEGER NOT NULL DEFAULT 1,
    CONSTRAINT "TallyExport_pkey" PRIMARY KEY ("guid")
);

-- Sales invoices already exported under change 06.12 keep their date.
INSERT INTO "TallyExport" ("guid", "kind", "number", "firstExportedAt", "lastExportedAt")
SELECT 'rejwin-sales-' || "id", 'sales', "number", "tallyExportedAt", "tallyExportedAt"
FROM "Invoice" WHERE "tallyExportedAt" IS NOT NULL
ON CONFLICT DO NOTHING;

-- The Tally ledger names already saved (Setting "tally.ledgers") are left exactly
-- as they are: nothing is deleted or renamed. The purchase settings are no longer
-- shown or used (change 07.2) but stay stored; the new standard names (change
-- 07.3) apply only where no name has been saved.
