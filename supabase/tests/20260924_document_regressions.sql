-- Run as database owner. Every fixture and counter change is rolled back.
begin;
do $$
declare
  owners uuid[];
  first_number text;
  second_number text;
  other_number text;
  before_docs text;
  after_docs text;
begin
  select array_agg(id order by id) into owners from auth.users;
  if cardinality(owners) < 2 then raise exception 'Need two existing users for isolation checks'; end if;
  perform set_config('request.jwt.claim.sub',owners[1]::text,true);
  first_number := public.next_invoice_number('QA','2088-04-01','');
  second_number := public.next_invoice_number('QA','2088-04-01','');
  if first_number <> 'QA/2088-89/01' or second_number <> 'QA/2088-89/02' then
    raise exception 'First-business sequence failed: %, %',first_number,second_number;
  end if;
  if public.next_quotation_number('QA','2088-04-01','') <> 'QA/2088-89/01' then
    raise exception 'Quotation sequence is not independent';
  end if;
  if public.next_invoice_number('QA','2089-04-01','') <> 'QA/2089-90/01' then
    raise exception 'Financial-year reset failed';
  end if;
  if public.document_financial_year('2089-03-31') <> 2088 then raise exception 'March boundary failed'; end if;
  perform set_config('request.jwt.claim.sub',owners[2]::text,true);
  other_number := public.next_invoice_number('QA','2088-04-01','');
  if other_number <> first_number then raise exception 'Businesses share a counter'; end if;
  insert into public.invoices(user_id,invoice_number,customer_name,invoice_date)
    values(owners[1],first_number,'Regression fixture','2088-04-01'),
          (owners[2],first_number,'Regression fixture','2088-04-01');
  begin
    insert into public.invoices(user_id,invoice_number,customer_name,invoice_date)
      values(owners[1],lower(first_number),'Duplicate fixture','2088-09-01');
    raise exception 'Duplicate invoice was accepted';
  exception when unique_violation then null;
  end;
  insert into public.quotations(user_id,quotation_number,customer_name,quotation_date)
    values(owners[1],first_number,'Regression fixture','2088-04-01'),
          (owners[2],first_number,'Regression fixture','2088-04-01');
  begin
    insert into public.quotations(user_id,quotation_number,customer_name,quotation_date)
      values(owners[1],first_number,'Duplicate fixture','2088-09-01');
    raise exception 'Duplicate quotation was accepted';
  exception when unique_violation then null;
  end;
  select md5(string_agg(row_to_json(i)::text, '' order by i.id)) into before_docs from public.invoices i;
  update public.customers set is_active=false where user_id=owners[1];
  update public.products set is_active=false where user_id=owners[1];
  select md5(string_agg(row_to_json(i)::text, '' order by i.id)) into after_docs from public.invoices i;
  if before_docs is distinct from after_docs then raise exception 'Catalog removal changed invoices'; end if;
  perform set_config('request.jwt.claim.sub','',true);
  begin
    perform public.next_invoice_number('QA','2088-04-01','');
    raise exception 'Unauthenticated allocation was accepted';
  exception when invalid_authorization_specification then null;
  end;
end;
$$;
rollback;
select 'PASS: business/year isolation, independent quotation sequence, duplicate rejection, preserved invoices, authentication; all test writes rolled back' as result;
