-- HSN/SAC master and product-master fields for Simplek.
-- Import only the current official GSTN HSN/SAC export; do not seed this table
-- with manually assembled or third-party data.

create extension if not exists pg_trgm;

create table if not exists public.uqc_master (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  description text not null,
  category text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists uqc_master_active_code_idx
  on public.uqc_master (code)
  where is_active;

create index if not exists uqc_master_description_trgm_idx
  on public.uqc_master using gin (description gin_trgm_ops);

-- Exact UQC codes and descriptions from gst_approved_quantity_list.pdf.
insert into public.uqc_master (code, description, category) values
  ('NOS', 'Numbers', 'Count and Packaging'),
  ('PCS', 'Pieces', 'Count and Packaging'),
  ('PAC', 'Packs', 'Count and Packaging'),
  ('BOX', 'Box', 'Count and Packaging'),
  ('BAG', 'Bags', 'Count and Packaging'),
  ('BAL', 'Bale', 'Count and Packaging'),
  ('BDL', 'Bundles', 'Count and Packaging'),
  ('BKL', 'Buckles', 'Count and Packaging'),
  ('BTL', 'Bottles', 'Count and Packaging'),
  ('BUN', 'Bunches', 'Count and Packaging'),
  ('CAN', 'Cans', 'Count and Packaging'),
  ('CTN', 'Cartons', 'Count and Packaging'),
  ('DOZ', 'Dozen', 'Count and Packaging'),
  ('DRM', 'Drum', 'Count and Packaging'),
  ('GGK', 'Great Gross', 'Count and Packaging'),
  ('GRS', 'Gross', 'Count and Packaging'),
  ('PRS', 'Pairs', 'Count and Packaging'),
  ('SET', 'Sets', 'Count and Packaging'),
  ('TUB', 'Tubes', 'Count and Packaging'),
  ('THD', 'Thousands', 'Count and Packaging'),
  ('GMS', 'Grams', 'Weight and Mass'),
  ('KGS', 'Kilograms', 'Weight and Mass'),
  ('QTL', 'Quintal', 'Weight and Mass'),
  ('TON', 'Tonnes (Metric Ton)', 'Weight and Mass'),
  ('MTS', 'Metric Ton', 'Weight and Mass'),
  ('TGM', 'Ten Grams', 'Weight and Mass'),
  ('MLT', 'Millilitre', 'Volume and Liquid'),
  ('LTR', 'Litres', 'Volume and Liquid'),
  ('KLR', 'Kilolitre', 'Volume and Liquid'),
  ('CBM', 'Cubic Meter', 'Volume and Liquid'),
  ('CCM', 'Cubic Centimeter', 'Volume and Liquid'),
  ('UGS', 'US Gallons', 'Volume and Liquid'),
  ('CMS', 'Centimeter', 'Length and Area'),
  ('MTR', 'Meters', 'Length and Area'),
  ('KME', 'Kilometre', 'Length and Area'),
  ('YDS', 'Yards', 'Length and Area'),
  ('GYD', 'Gross Yards', 'Length and Area'),
  ('SQF', 'Square Feet', 'Length and Area'),
  ('SQM', 'Square Meters', 'Length and Area'),
  ('SQY', 'Square Yards', 'Length and Area'),
  ('ROL', 'Rolls', 'Length and Area'),
  ('BOU', 'Billions of Units', 'Miscellaneous'),
  ('TBS', 'Tablets', 'Miscellaneous'),
  ('UNT', 'Units', 'Miscellaneous'),
  ('OTH', 'Others (For any unlisted measurement units)', 'Miscellaneous')
on conflict (code) do update set
  description = excluded.description,
  category = excluded.category,
  is_active = true,
  updated_at = now();

create table if not exists public.hsn_sac_master (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  code_type text not null check (code_type in ('HSN', 'SAC')),
  digit_level smallint not null check (digit_level in (2, 4, 6, 8)),
  chapter text,
  heading text,
  description text not null,
  gst_rate numeric(5, 2),
  cgst_rate numeric(5, 2),
  sgst_rate numeric(5, 2),
  igst_rate numeric(5, 2),
  cess_rate numeric(5, 2) not null default 0,
  is_active boolean not null default true,
  search_keywords text,
  updated_at timestamptz not null default now(),
  constraint hsn_sac_master_code_format check (code ~ '^[0-9]+$'),
  constraint hsn_sac_master_code_length check (char_length(code) = digit_level),
  constraint hsn_sac_master_code_unique unique (code, code_type)
);

create index if not exists hsn_sac_master_active_code_idx
  on public.hsn_sac_master (code)
  where is_active;

create index if not exists hsn_sac_master_description_trgm_idx
  on public.hsn_sac_master using gin (description gin_trgm_ops);

create index if not exists hsn_sac_master_keywords_trgm_idx
  on public.hsn_sac_master using gin (search_keywords gin_trgm_ops);

-- Preserve the existing products table and add only the fields needed by the
-- product form. Existing rows remain valid because these fields are nullable.
alter table public.products
  add column if not exists name text,
  add column if not exists product_type text,
  add column if not exists uqc_code text references public.uqc_master(code),
  add column if not exists purchase_price numeric(14, 2),
  add column if not exists selling_price numeric(14, 2),
  add column if not exists sku text,
  add column if not exists is_active boolean not null default true,
  add column if not exists tax_inclusive boolean not null default false,
  add column if not exists hsn_sac_id uuid references public.hsn_sac_master(id),
  add column if not exists hsn_sac_code text,
  add column if not exists hsn_sac_description text,
  add column if not exists gst_rate numeric(5, 2),
  add column if not exists cgst_rate numeric(5, 2),
  add column if not exists sgst_rate numeric(5, 2),
  add column if not exists igst_rate numeric(5, 2),
  add column if not exists cess_rate numeric(5, 2),
  add column if not exists updated_at timestamptz not null default now();

alter table public.products
  add constraint products_product_type_check
  check (product_type is null or product_type in ('product', 'service'));

create index if not exists products_hsn_sac_id_idx
  on public.products (hsn_sac_id);

create index if not exists products_uqc_code_idx
  on public.products (uqc_code);

-- Invoice quantities and UQCs are separate fields. UQC descriptions remain in
-- the master table; invoice items store only the authoritative UQC code.
alter table public.invoice_items
  add column if not exists product_id uuid references public.products(id),
  add column if not exists quantity numeric(14, 3),
  add column if not exists uqc_code text references public.uqc_master(code),
  add column if not exists unit_price numeric(14, 2),
  add column if not exists taxable_amount numeric(14, 2),
  add column if not exists gst_rate numeric(5, 2),
  add column if not exists tax_amount numeric(14, 2),
  add column if not exists total_amount numeric(14, 2);

create index if not exists invoice_items_product_uqc_idx
  on public.invoice_items (product_id, uqc_code);

-- Staging data can be loaded from a fresh official GSTN export and upserted
-- with ON CONFLICT (code, code_type) DO UPDATE. This keeps future master
-- updates data-only and avoids Flutter code changes.
