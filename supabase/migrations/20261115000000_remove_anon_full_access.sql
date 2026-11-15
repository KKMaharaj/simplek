-- Remove policies that were created directly in the live project (they are in
-- no earlier migration) and gave anonymous callers full read and write access
-- to every business's rows. The app only uses these tables while signed in,
-- where the per-owner policies from 20260831000000_customer_product_rls.sql
-- apply. Payments are written only through record_invoice_payment.
begin;

drop policy if exists "Allow all customers" on public.customers;
drop policy if exists "Allow all products" on public.products;
drop policy if exists "Allow all payments" on public.payments;

commit;
