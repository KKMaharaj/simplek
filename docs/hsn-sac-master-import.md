# HSN/SAC master import and update

The app never ships with a hand-maintained HSN/SAC list. Load the complete
master from the current official GSTN/GST Portal export before enabling GST
product creation.

## Official source

GSTN's HSN search and GSTR-1 Table 12 provide an updated Excel download of HSN
and SAC codes with descriptions. Download a fresh export from the GST Portal's
**Download HSN Codes List** option. The GSTN advisory confirms that this export
contains the updated HSN and SAC lists and descriptions.

## Required import columns

Prepare a CSV with these headers:

```text
code,code_type,digit_level,chapter,heading,description,gst_rate,cgst_rate,sgst_rate,igst_rate,cess_rate,is_active,search_keywords,updated_at
```

Use only values present in the official export. Tax rates may be blank when the
official source does not supply them; they must not be guessed.

## Import/update procedure

1. Apply `supabase/migrations/20260810_hsn_sac_master.sql` in the Supabase SQL
   Editor or through the Supabase CLI.
2. Load the official CSV into a staging table using the Supabase Dashboard's
   CSV import feature or a service-role administration job.
3. Upsert into `public.hsn_sac_master` using the unique key `(code, code_type)`.
4. Mark codes omitted from a superseding official master as inactive instead of
   deleting them, so old invoices retain their reference data.
5. Record the official export date and source URL in the import job's audit log.

The mobile app searches only active master rows. HSN/SAC values in GST product
forms are selected from this table and cannot be typed as arbitrary codes.
