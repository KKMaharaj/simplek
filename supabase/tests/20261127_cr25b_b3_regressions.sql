-- CR-25B B3 (25 Nov 2026): save_invoice repeats the paise rounding rule,
-- refuses a mismatch from the current app, and recalculates for older app
-- versions. Run as database owner with at least one user in auth.users.
-- Every change is rolled back.
begin;
do $$
declare
  owner_id uuid;
  inv public.invoices;
  item record;
  failed boolean;
  strict_header jsonb := '{"customer_name":"B3 fixture","invoice_date":"2091-07-01",
    "terms":"t","tax_type":"cgst_sgst","money_rule":"paise-v1"}';
  -- 5% on ₹101: tax 5.05 = CGST 2.53 + SGST 2.52.
  five jsonb := '[{"item_name":"Five","quantity":1,"unit_price":101,"gst_rate":5,
    "taxable_amount":101,"tax_amount":5.05,"cgst_amount":2.53,"sgst_amount":2.52,
    "igst_amount":0,"total_amount":106.05}]';
  five_totals jsonb := '{"subtotal":101,"tax_amount":5.05,"cgst_amount":2.53,
    "sgst_amount":2.52,"igst_amount":0,"total_amount":106}';
begin
  select id into owner_id from auth.users order by id limit 1;
  if owner_id is null then raise exception 'Need an existing user'; end if;
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', owner_id::text, true);

  -- The current app's amounts are accepted when they follow the rule.
  inv := public.save_invoice(gen_random_uuid(), strict_header || five_totals, five, false, 'QBB');
  if (inv.cgst_amount, inv.sgst_amount, inv.tax_amount, inv.total_amount)
     is distinct from (2.53::numeric, 2.52::numeric, 5.05::numeric, 106::numeric) then
    raise exception '5%% on 101 stored %, %, %, %',
      inv.cgst_amount, inv.sgst_amount, inv.tax_amount, inv.total_amount;
  end if;
  select cgst_amount, sgst_amount into item from public.invoice_items where invoice_id = inv.id;
  if (item.cgst_amount, item.sgst_amount) is distinct from (2.53::numeric, 2.52::numeric) then
    raise exception 'Line split stored % + %', item.cgst_amount, item.sgst_amount;
  end if;

  -- A line that splits 2.53 + 2.53 is refused.
  failed := false;
  begin
    perform public.save_invoice(gen_random_uuid(), strict_header || five_totals,
      jsonb_set(five, '{0,sgst_amount}', '2.53'), false, 'QBB');
  exception when sqlstate '22000' then failed := true;
  end;
  if not failed then raise exception 'A line with CGST + SGST <> tax was accepted'; end if;

  -- A total that doesn't match is refused.
  failed := false;
  begin
    perform public.save_invoice(gen_random_uuid(),
      strict_header || five_totals || '{"total_amount":107}', five, false, 'QBB');
  exception when sqlstate '22000' then failed := true;
  end;
  if not failed then raise exception 'A wrong total was accepted'; end if;

  -- Tax with tax type "none" is refused.
  failed := false;
  begin
    perform public.save_invoice(gen_random_uuid(),
      strict_header || five_totals || '{"tax_type":"none"}', five, false, 'QBB');
  exception when sqlstate '22000' then failed := true;
  end;
  if not failed then raise exception 'Tax type none with tax was accepted'; end if;

  -- 3 × ₹33.33 @ 18%, 1.5 × ₹250.10 @ 12% and a 0% line, as IGST.
  inv := public.save_invoice(gen_random_uuid(),
    strict_header || '{"tax_type":"igst","subtotal":499.14,"tax_amount":63.02,
      "cgst_amount":0,"sgst_amount":0,"igst_amount":63.02,"total_amount":562}',
    '[{"item_name":"A","quantity":3,"unit_price":33.33,"gst_rate":18,
       "taxable_amount":99.99,"tax_amount":18,"igst_amount":18,"total_amount":117.99},
      {"item_name":"B","quantity":1.5,"unit_price":250.10,"gst_rate":12,
       "taxable_amount":375.15,"tax_amount":45.02,"igst_amount":45.02,"total_amount":420.17},
      {"item_name":"C","quantity":2,"unit_price":12,"gst_rate":0,
       "taxable_amount":24,"tax_amount":0,"igst_amount":0,"total_amount":24}]',
    false, 'QBB');
  if (inv.tax_type, inv.igst_amount, inv.cgst_amount, inv.total_amount)
     is distinct from ('igst', 63.02::numeric, 0::numeric, 562::numeric) then
    raise exception 'Mixed IGST invoice stored %, %, %, %',
      inv.tax_type, inv.igst_amount, inv.cgst_amount, inv.total_amount;
  end if;

  -- ₹1.25 crore: 2.5 × ₹50,00,000.40 @ 18%.
  inv := public.save_invoice(gen_random_uuid(),
    strict_header || '{"subtotal":12500001,"tax_amount":2250000.18,
      "cgst_amount":1125000.09,"sgst_amount":1125000.09,"igst_amount":0,
      "total_amount":14750001}',
    '[{"item_name":"Big","quantity":2.5,"unit_price":5000000.40,"gst_rate":18,
       "taxable_amount":12500001,"tax_amount":2250000.18,"cgst_amount":1125000.09,
       "sgst_amount":1125000.09,"igst_amount":0,"total_amount":14750001.18}]',
    false, 'QBB');
  if inv.total_amount <> 14750001 or inv.balance_amount <> 14750001 then
    raise exception '1.25 crore stored %', inv.total_amount;
  end if;

  -- An older app (no money_rule) keeps working: its amounts are replaced by
  -- the server's. It split 5.05 as 2.525 + 2.525 and sent an unrounded tax.
  inv := public.save_invoice(gen_random_uuid(),
    '{"customer_name":"B3 old app","invoice_date":"2091-07-02","tax_type":"cgst_sgst",
      "subtotal":200.99,"tax_amount":23.0482,"cgst_amount":11.5241,"sgst_amount":11.5241,
      "total_amount":224}',
    '[{"item_name":"Old A","quantity":1,"unit_price":101,"gst_rate":5,
       "taxable_amount":101,"tax_amount":5.05,"cgst_amount":2.525,"sgst_amount":2.525,
       "total_amount":106.05},
      {"item_name":"Old B","quantity":3,"unit_price":33.33,"gst_rate":18,
       "taxable_amount":99.99,"tax_amount":17.9982,"cgst_amount":8.9991,"sgst_amount":8.9991,
       "total_amount":117.9882}]',
    false, 'QBB');
  if (inv.subtotal, inv.tax_amount, inv.cgst_amount, inv.sgst_amount, inv.total_amount)
     is distinct from (200.99::numeric, 23.05::numeric, 11.53::numeric, 11.52::numeric, 224::numeric) then
    raise exception 'Older app invoice stored %, %, %, %, %',
      inv.subtotal, inv.tax_amount, inv.cgst_amount, inv.sgst_amount, inv.total_amount;
  end if;
  select tax_amount, cgst_amount, sgst_amount into item
    from public.invoice_items where invoice_id = inv.id and item_name = 'Old B';
  if (item.tax_amount, item.cgst_amount, item.sgst_amount)
     is distinct from (18::numeric, 9::numeric, 9::numeric) then
    raise exception 'Older app line stored %, %, %', item.tax_amount, item.cgst_amount, item.sgst_amount;
  end if;

  -- An edit follows the same rule (and keeps the audit of B1).
  inv := public.save_invoice(inv.id, strict_header || five_totals, five, true, 'QBB');
  if inv.total_amount <> 106 or inv.cgst_amount <> 2.53 then
    raise exception 'Edit stored %, %', inv.total_amount, inv.cgst_amount;
  end if;

  raise notice 'CR-25B B3 regressions passed';
end;
$$;
select 'B3 regressions reached the end' as result;
rollback;
