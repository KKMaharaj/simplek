-- CR-25B B4.6: run the privacy clean-up every night at 03:00 IST (21:30
-- UTC), after the 02:30 IST backup. pg_cron calls the privacy-daily edge
-- function through pg_net. The function only does work that is already due
-- (accounts on day 31, sign-ups never completed after 30 days, year-old
-- audit entries, week-old data exports), so it needs no secret; it uses
-- the project's own service-role key inside Supabase.
--
-- Apply after deploying the function:
--   supabase functions deploy privacy-daily --no-verify-jwt
-- On 27 Nov 2026 the clean-up would have removed 0 of the 7 logins.
begin;

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

select cron.unschedule(jobid) from cron.job where jobname = 'privacy-daily';

select cron.schedule(
  'privacy-daily',
  '30 21 * * *',
  $job$
  select net.http_post(
    url := 'https://vvzaoxhygzhentywnlwr.supabase.co/functions/v1/privacy-daily',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
  $job$
);

commit;
