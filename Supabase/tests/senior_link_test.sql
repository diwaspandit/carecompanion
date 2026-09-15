-- Senior device link contract: only a senior member links their login to a senior record, and
-- only that linked login may write HealthKit-sourced snapshots. Run via Supabase/tests/run_local.sh.
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000d1'),  -- Diwas, Link family (family)
  ('00000000-0000-0000-0000-0000000000d2'),  -- Maya, Link family (senior)
  ('00000000-0000-0000-0000-0000000000d3'),  -- second senior member, Link family
  ('00000000-0000-0000-0000-0000000000d4');  -- outsider

set role authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select set_config('test.link_id', id::text, false), set_config('test.link_code', invite_code, false)
  from public.create_care_account('Link family', 'family');
insert into public.account_seniors (id, account_id, name, age, city, time_zone_identifier)
  values ('20000000-0000-0000-0000-000000000001', current_setting('test.link_id')::uuid,
          'Maya Sharma', 74, 'Kathmandu, Nepal', 'Asia/Kathmandu');

-- A member cannot pre-link a senior on insert.
do $$ begin
  begin
    insert into public.account_seniors (account_id, name, age, profile_id)
      values (current_setting('test.link_id')::uuid, 'Sneaky', 70, '00000000-0000-0000-0000-0000000000d1');
    raise exception 'FAIL: senior inserted with profile_id';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Family member cannot claim, directly or through the RPC.
do $$ begin
  begin
    perform public.claim_senior_profile('20000000-0000-0000-0000-000000000001');
    raise exception 'FAIL: family member claimed senior';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.account_seniors set profile_id = auth.uid()
      where id = '20000000-0000-0000-0000-000000000001';
    raise exception 'FAIL: family member set profile_id directly';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Unlinked: nobody may write HealthKit rows, manual rows are fine.
do $$ begin
  begin
    insert into public.health_snapshots (account_id, senior_id, snapshot_date, source)
      values (current_setting('test.link_id')::uuid, '20000000-0000-0000-0000-000000000001', '2026-09-01', 'healthkit');
    raise exception 'FAIL: family member wrote healthkit snapshot';
  exception when insufficient_privilege then null;
  end;
end $$;
insert into public.health_snapshots (account_id, senior_id, snapshot_date, source)
  values (current_setting('test.link_id')::uuid, '20000000-0000-0000-0000-000000000001', '2026-09-01', 'manual');

-- Maya joins as senior and claims her record.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d2', false);
select public.join_care_account(current_setting('test.link_code'), 'senior');
select public.claim_senior_profile('20000000-0000-0000-0000-000000000001');
do $$ begin
  assert (select profile_id from public.account_seniors where id = '20000000-0000-0000-0000-000000000001')
    = '00000000-0000-0000-0000-0000000000d2'::uuid, 'Maya should be linked';
end $$;
-- Claiming again is idempotent.
select public.claim_senior_profile('20000000-0000-0000-0000-000000000001');
insert into public.health_snapshots (account_id, senior_id, snapshot_date, source)
  values (current_setting('test.link_id')::uuid, '20000000-0000-0000-0000-000000000001', '2026-09-01', 'healthkit');
update public.health_snapshots set steps = 100
  where senior_id = '20000000-0000-0000-0000-000000000001' and source = 'healthkit';

-- A second senior member cannot take over an already linked record.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d3', false);
select public.join_care_account(current_setting('test.link_code'), 'senior');
do $$ begin
  begin
    perform public.claim_senior_profile('20000000-0000-0000-0000-000000000001');
    raise exception 'FAIL: second senior took over linked record';
  exception when unique_violation then null;
  end;
end $$;

-- Family member still cannot rewrite Maya's HealthKit rows once she is linked.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
do $$
declare affected int;
begin
  update public.health_snapshots set steps = 1
    where senior_id = '20000000-0000-0000-0000-000000000001' and source = 'healthkit';
  get diagnostics affected = row_count;
  assert affected = 0, 'family member must not rewrite healthkit rows';
end $$;

-- Outsider cannot claim.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d4', false);
do $$ begin
  begin
    perform public.claim_senior_profile('20000000-0000-0000-0000-000000000001');
    raise exception 'FAIL: outsider claimed senior';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
select 'SENIOR LINK TESTS PASSED' as result;
