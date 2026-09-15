-- Contract test for 20260915000001_production_features.sql.
-- Runs after rls_test.sql in the same database: reuses Diwas (a), Maya (b), the outsider (c),
-- the Sharma account and Maya's senior record 10000000-...-0001.
\set ON_ERROR_STOP on

-- rls_test.sql ran in its own session, so re-derive the ids it stored.
select set_config('test.sharma_id', id::text, false) from public.care_accounts where name = 'Sharma family';
select set_config('test.other_id', id::text, false) from public.care_accounts where name = 'Other family';

set role authenticated;

-- Diwas fills in his phone, Maya's emergency contact, a dosed medication and a message.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
update public.profiles set display_name = 'Diwas', phone = '+1 512 555 0142'
  where id = '00000000-0000-0000-0000-00000000000a';
insert into public.emergency_contacts (account_id, senior_id, name, relation, phone)
  values (current_setting('test.sharma_id')::uuid, '10000000-0000-0000-0000-000000000001',
          'Sunita Sharma', 'Daughter', '+977 98 4100 2233');
insert into public.medications (account_id, senior_id, name, dosage, scheduled_time)
  values (current_setting('test.sharma_id')::uuid, '10000000-0000-0000-0000-000000000001',
          'Amlodipine', '5 mg', '8:00 AM');
insert into public.messages (account_id, body)
  values (current_setting('test.sharma_id')::uuid, 'Did you sleep well, Aama?');

do $$ begin
  assert (select count(*) from public.messages) = 1, 'Diwas should see his message';
  assert (select sender_profile_id from public.messages limit 1) = '00000000-0000-0000-0000-00000000000a',
    'sender defaults to the caller';
  assert (select dosage from public.medications where name = 'Amlodipine') = '5 mg', 'dosage is stored';
end $$;

-- A family member cannot link their own login to the senior record, directly or via RPC.
do $$ begin
  begin
    update public.account_seniors set profile_id = '00000000-0000-0000-0000-00000000000a'
      where id = '10000000-0000-0000-0000-000000000001';
    raise exception 'FAIL: family member linked themself as the senior';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.claim_senior('10000000-0000-0000-0000-000000000001');
    raise exception 'FAIL: family member claimed the senior';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Editing senior details still works for family members.
update public.account_seniors set city = 'Kathmandu' where id = '10000000-0000-0000-0000-000000000001';

-- Maya (senior member) links her login, sees the family data and replies.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select public.claim_senior('10000000-0000-0000-0000-000000000001');
update public.profiles set display_name = 'Maya', phone = '+977 98 5100 1122'
  where id = '00000000-0000-0000-0000-00000000000b';
insert into public.messages (account_id, body)
  values (current_setting('test.sharma_id')::uuid, 'Yes, 7 hours!');

do $$ begin
  assert (select profile_id from public.account_seniors where id = '10000000-0000-0000-0000-000000000001')
    = '00000000-0000-0000-0000-00000000000b', 'Maya should be linked to her senior record';
  assert (select count(*) from public.emergency_contacts) = 1, 'Maya sees her emergency contact';
  assert (select count(*) from public.messages) = 2, 'Maya sees the family conversation';
end $$;

-- Nobody can spoof a sender.
do $$ begin
  begin
    insert into public.messages (account_id, sender_profile_id, body)
      values (current_setting('test.sharma_id')::uuid, '00000000-0000-0000-0000-00000000000a', 'spoofed');
    raise exception 'FAIL: message sent as someone else';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Diwas can read Maya's phone through the shared account.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
do $$ begin
  assert (select phone from public.profiles where id = '00000000-0000-0000-0000-00000000000b') = '+977 98 5100 1122',
    'co-member phone should be readable';
end $$;

-- Outsider: no contacts, no messages, no claiming, no writes into Sharma.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
do $$ begin
  assert (select count(*) from public.emergency_contacts) = 0, 'outsider must not read Sharma contacts';
  assert (select count(*) from public.messages) = 0, 'outsider must not read Sharma messages';
  begin
    insert into public.messages (account_id, body) values (current_setting('test.sharma_id')::uuid, 'hi');
    raise exception 'FAIL: outsider posted into Sharma conversation';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.emergency_contacts (account_id, senior_id, name, phone)
      values (current_setting('test.other_id')::uuid, '10000000-0000-0000-0000-000000000001', 'x', '1');
    raise exception 'FAIL: outsider attached a contact to a foreign senior';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.claim_senior('10000000-0000-0000-0000-000000000001');
    raise exception 'FAIL: outsider claimed a foreign senior';
  exception when insufficient_privilege then null;
  end;
end $$;

-- The outsider deletes their account: their single-member family goes with them.
select public.delete_my_account();

reset role;
do $$ begin
  assert not exists (select 1 from auth.users where id = '00000000-0000-0000-0000-00000000000c'),
    'outsider login should be gone';
  assert not exists (select 1 from public.care_accounts where id = current_setting('test.other_id')::uuid),
    'single-member account should be deleted';
  assert exists (select 1 from public.care_accounts where id = current_setting('test.sharma_id')::uuid),
    'Sharma account must be untouched';
end $$;

-- Maya deletes her account: the shared family keeps its data, her senior link is cleared.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select public.delete_my_account();

reset role;
do $$ begin
  assert exists (select 1 from public.care_accounts where id = current_setting('test.sharma_id')::uuid),
    'shared account survives a member deleting themself';
  assert (select count(*) from public.account_members where account_id = current_setting('test.sharma_id')::uuid) = 1,
    'only Diwas remains a member';
  assert (select profile_id from public.account_seniors where id = '10000000-0000-0000-0000-000000000001') is null,
    'senior link is cleared when the senior deletes their login';
  assert (select count(*) from public.messages) = 2, 'conversation history is kept for the family';
end $$;

-- anon still reads nothing new.
set role anon;
do $$ begin
  begin
    perform 1 from public.messages;
    raise exception 'FAIL: anon can read messages';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
select 'PRODUCTION RLS TESTS PASSED' as result;
