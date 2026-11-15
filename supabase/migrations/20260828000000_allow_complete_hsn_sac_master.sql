-- The official HSN/SAC workbook includes intermediate 5- and 7-digit HSN
-- classifications. Keep every official master row rather than discarding them.
-- The required 2-, 4-, 6-, and 8-digit levels remain supported.

alter table public.hsn_sac_master
  drop constraint if exists hsn_sac_master_code_length;

alter table public.hsn_sac_master
  drop constraint if exists hsn_sac_master_digit_level_check;

alter table public.hsn_sac_master
  add constraint hsn_sac_master_digit_level_check
  check (digit_level in (2, 4, 5, 6, 7, 8));
