# Official HSN/SAC import files

Generated from `C:\Users\HP\Downloads\HSN_SAC.xlsx`.

| File | Rows | Target table |
| --- | ---: | --- |
| `hsn_master_import.csv` | 21,932 | `public.hsn_sac_master` |
| `sac_master_import.csv` | 681 | `public.hsn_sac_master` |

## Import order

1. Apply `../migrations/20260828000000_allow_complete_hsn_sac_master.sql` in the
   Supabase SQL Editor. The official HSN sheet includes 5- and 7-digit
   intermediate classifications in addition to the required 2/4/6/8 levels.
2. In the Supabase Table Editor, select `hsn_sac_master` and import
   `hsn_master_import.csv`.
3. Import `sac_master_import.csv` into the same table.
4. Keep the following target columns mapped: `code`, `code_type`,
   `digit_level`, `description`, and `is_active`. Leave all tax-rate columns
   blank because this source workbook does not provide official rate data.

## Source integrity notes

- One HSN row, code `52083110`, had a blank description in the source workbook
  and is intentionally excluded; no description has been invented.
- Two formatted duplicates (`2307 00`/`230700` and `2514 00`/`251400`) were
  normalized to their six-digit code and deduplicated by retaining the detailed
  official description.

The import CSVs do not include `updated_at`; the database default supplies it.

# States and districts (LGD)

| File | Rows | Target table |
| --- | ---: | --- |
| `lgd_states.csv` | 36 | `public.states` |
| `lgd_districts.csv` | 790 | `public.districts` |

Source: Local Government Directory, https://lgdirectory.gov.in, "Download
Directory" → All Districts of India (XLS), downloaded by the owner on
26 Nov 2026. Converted to CSV with Excel and imported with
`dart run tool/import_lgd.dart <districts.csv> 2026-11-26`, which also writes
`assets/data/states_districts.json` and
`../migrations/20261126000002_seed_states_districts.sql`. GST state codes
are kept in `lib/india_states.dart` (LGD codes differ for Andhra Pradesh,
Ladakh and Dadra and Nagar Haveli and Daman and Diu).
