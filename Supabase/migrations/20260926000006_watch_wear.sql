-- Minutes the Apple Watch was worn each hour, inferred from heart-rate samples.
-- value is worn minutes (15-minute slices). value_secondary is the last sample time.

do $$
declare
  constraint_name text;
begin
  select con.conname into constraint_name
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace nsp on nsp.oid = rel.relnamespace
  where nsp.nspname = 'public'
    and rel.relname = 'health_readings'
    and con.contype = 'c'
    and pg_get_constraintdef(con.oid) ilike '%heart_rate%';
  if constraint_name is not null then
    execute format('alter table public.health_readings drop constraint %I', constraint_name);
  end if;
end $$;

alter table public.health_readings add constraint health_readings_kind_check
  check (kind in ('heart_rate', 'blood_pressure', 'steps', 'sleep', 'worn'));
