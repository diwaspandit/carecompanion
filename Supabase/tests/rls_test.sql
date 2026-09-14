-- RLS contract test: two families; each member sees and writes only their own account.
-- Run via Supabase/tests/run_local.sh (plain Postgres + local_stub.sql).
\set ON_ERROR_STOP on

insert into auth.users (id) values
  ('00000000-0000-0000-0000-00000000000a'),  -- Diwas, Sharma family
  ('00000000-0000-0000-0000-00000000000b'),  -- Maya, Sharma family
  ('00000000-0000-0000-0000-00000000000c');  -- outsider, another family

set role authenticated;

-- Diwas creates the family account and adds Maya as the monitored senior.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
select set_config('test.sharma_id', id::text, false), set_config('test.sharma_code', invite_code, false)
  from public.create_care_account('Sharma family', 'family');
insert into public.account_seniors (id, account_id, name, age, city, time_zone_identifier)
  values ('10000000-0000-0000-0000-000000000001', current_setting('test.sharma_id')::uuid,
          'Maya Sharma', 74, 'Kathmandu, Nepal', 'Asia/Kathmandu');

-- Maya joins with the invite code and checks in.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select public.join_care_account(current_setting('test.sharma_code'), 'senior');
insert into public.check_ins (account_id, senior_id)
  values (current_setting('test.sharma_id')::uuid, '10000000-0000-0000-0000-000000000001');
insert into public.alerts (account_id, senior_id)
  values (current_setting('test.sharma_id')::uuid, '10000000-0000-0000-0000-000000000001');

-- Diwas sees Maya's data.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
do $$ begin
  assert (select count(*) from public.check_ins) = 1, 'Diwas should see Maya''s check-in';
  assert (select count(*) from public.alerts where not acknowledged) = 1, 'Diwas should see the SOS';
  assert (select count(*) from public.profiles) = 2, 'Diwas should see both co-member profiles';
  assert (select count(*) from public.account_members) = 2, 'roster should list both members';
end $$;

-- A second open SOS for the same senior is rejected.
do $$ begin
  begin
    insert into public.alerts (account_id, senior_id)
      values (current_setting('test.sharma_id')::uuid, '10000000-0000-0000-0000-000000000001');
    raise exception 'FAIL: duplicate open SOS accepted';
  exception when unique_violation then null;
  end;
end $$;

-- Outsider: own account only, no cross-account reads.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
select set_config('test.other_id', id::text, false) from public.create_care_account('Other family');
do $$ begin
  assert (select count(*) from public.check_ins) = 0, 'outsider must not read Sharma check-ins';
  assert (select count(*) from public.alerts) = 0, 'outsider must not read Sharma alerts';
  assert (select count(*) from public.account_seniors) = 0, 'outsider must not read Sharma seniors';
  assert (select count(*) from public.care_accounts) = 1, 'outsider sees only own account';
  assert (select count(*) from public.profiles) = 1, 'outsider sees only own profile';
end $$;

-- Outsider cannot write into the Sharma account.
do $$ begin
  begin
    insert into public.check_ins (account_id, senior_id)
      values (current_setting('test.sharma_id')::uuid, '10000000-0000-0000-0000-000000000001');
    raise exception 'FAIL: outsider wrote into Sharma account';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Outsider cannot attach Maya's senior id to their own account.
do $$ begin
  begin
    insert into public.check_ins (account_id, senior_id)
      values (current_setting('test.other_id')::uuid, '10000000-0000-0000-0000-000000000001');
    raise exception 'FAIL: outsider attached foreign senior';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Outsider cannot update or acknowledge Sharma alerts (RLS filters to zero rows).
do $$
declare affected int;
begin
  update public.alerts set acknowledged = true;
  get diagnostics affected = row_count;
  assert affected = 0, 'outsider must not acknowledge Sharma alerts';
end $$;

-- Wrong invite code is rejected.
do $$ begin
  begin
    perform public.join_care_account('NOPE0000');
    raise exception 'FAIL: bogus invite accepted';
  exception when no_data_found then null;
  end;
end $$;

-- anon role reads nothing.
reset role;
set role anon;
do $$ begin
  begin
    perform 1 from public.check_ins;
    raise exception 'FAIL: anon can read check_ins';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
select 'RLS TESTS PASSED' as result;
