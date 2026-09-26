-- Two daily mood checks, plus a family "ask now" stamp the senior's phone and watch both see.
alter table public.account_seniors
  add column if not exists mood_morning text not null default '9:00 AM',
  add column if not exists mood_evening text not null default '6:00 PM',
  add column if not exists mood_prompt_at timestamptz;

do $$
begin
  alter publication supabase_realtime add table public.account_seniors;
exception
  when duplicate_object then null;
end $$;
