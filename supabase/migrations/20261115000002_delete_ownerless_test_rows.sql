-- Delete ownerless test rows created during development on 2026-08-10 and
-- 2026-08-29, before any user account existed. No user could see them.
-- Requested by the business owner on 2026-11-15; a full backup taken that day
-- is kept outside the repository.
--
-- Effects on rows that do have an owner: the line item on invoice
-- INV/2026-27/0008 (Malnad Kitchen) loses its link to the product "auditing"
-- (invoice_items.product_id is ON DELETE SET NULL) and keeps its name and
-- amounts. No owned invoice references these customers. The quotation's one
-- line item is removed with it (ON DELETE CASCADE).
--
-- Rows are matched by id and only while still ownerless, so this changes
-- nothing on any other database.
begin;

-- Quotation QTN/2026-27/0001 (draft, customer "kk") and its line item
delete from public.quotations
where id = '44417afd-bad8-428e-ad28-50d5c1c600f0' and user_id is null;

-- Product "auditing"
delete from public.products
where id = 'b1dea02f-4124-4e00-bcaf-981a451cef19' and user_id is null;

-- Customers: Test Customer, kk, malnad kitchen, Malnad Kitchen, Akshay K K
delete from public.customers
where user_id is null
  and id in (
    'e6083b01-f4d8-4829-82ae-11499fefd592',
    'b80c406d-1977-44d2-8543-687e0bf55533',
    'cc06587b-ee80-41b9-b3d2-008183544c36',
    'bbe9300f-405c-45c0-9045-f1db6e9b889a',
    'a863c427-b3c1-43a8-b591-64bba110db61'
  );

commit;
