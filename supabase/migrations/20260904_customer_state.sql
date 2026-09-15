alter table public.customers
  add column if not exists state text;

update public.customers
set state = case left(upper(trim(gstin)), 2)
  when '01' then 'Jammu and Kashmir'
  when '02' then 'Himachal Pradesh'
  when '03' then 'Punjab'
  when '04' then 'Chandigarh'
  when '05' then 'Uttarakhand'
  when '06' then 'Haryana'
  when '07' then 'Delhi'
  when '08' then 'Rajasthan'
  when '09' then 'Uttar Pradesh'
  when '10' then 'Bihar'
  when '11' then 'Sikkim'
  when '12' then 'Arunachal Pradesh'
  when '13' then 'Nagaland'
  when '14' then 'Manipur'
  when '15' then 'Mizoram'
  when '16' then 'Tripura'
  when '17' then 'Meghalaya'
  when '18' then 'Assam'
  when '19' then 'West Bengal'
  when '20' then 'Jharkhand'
  when '21' then 'Odisha'
  when '22' then 'Chhattisgarh'
  when '23' then 'Madhya Pradesh'
  when '24' then 'Gujarat'
  when '25' then 'Dadra and Nagar Haveli and Daman and Diu'
  when '26' then 'Dadra and Nagar Haveli and Daman and Diu'
  when '27' then 'Maharashtra'
  when '29' then 'Karnataka'
  when '30' then 'Goa'
  when '31' then 'Lakshadweep'
  when '32' then 'Kerala'
  when '33' then 'Tamil Nadu'
  when '34' then 'Puducherry'
  when '35' then 'Andaman and Nicobar Islands'
  when '36' then 'Telangana'
  when '37' then 'Andhra Pradesh'
  when '38' then 'Ladakh'
end
where (state is null or trim(state) = '')
  and gstin is not null
  and left(upper(trim(gstin)), 2) in (
    '01','02','03','04','05','06','07','08','09','10','11','12','13','14',
    '15','16','17','18','19','20','21','22','23','24','25','26','27','29',
    '30','31','32','33','34','35','36','37','38'
  );

comment on column public.customers.state is
  'Required by the app for GST place-of-supply determination; existing legacy rows may be null.';
