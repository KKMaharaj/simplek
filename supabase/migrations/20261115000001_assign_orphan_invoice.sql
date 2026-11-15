-- Give the one ownerless invoice an owner so it appears in the app again.
-- INV/2026-27/0008 (draft, customer "kk") was created on 2026-08-29 before
-- row ownership existed, so 20260904000001_invoice_rls.sql could not assign
-- it. The business owner chose Malnad Kitchen (account 04453ceb...), which
-- already has a matching customer. Its number does not collide with or affect
-- that business's sequence. On any other database this changes nothing.
begin;

update public.invoices
set user_id = '04453ceb-76c1-4cd7-87c3-788ff59e825d'
where id = 'aa278784-3931-472d-bbba-092075295ce5'
  and user_id is null
  and exists (select 1 from auth.users where id = '04453ceb-76c1-4cd7-87c3-788ff59e825d');

commit;
