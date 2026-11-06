// Isolated PostgreSQL execution; no hosted customer records are modified.
// npm install --prefix .tools/explore-tests @electric-sql/pglite
// NODE_PATH=.tools/explore-tests/node_modules node --test supabase/tests/customer_explore_preferences.test.cjs
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { PGlite } = require('@electric-sql/pglite');

test('ordered profile preferences and provider directory execute in PostgreSQL', async (t) => {
  const db = new PGlite();
  t.after(() => db.close());
  // Minimal schema isolates these two functions. Auth helpers model the existing
  // viewer/active-account separation; full RLS remains covered by suspension tests.
  await db.exec(`
    create schema private; create schema auth; create schema storage;
    create table public.users(user_id uuid primary key, full_name text, phone text,
      profile_photo_url text, is_active boolean default true);
    create table public.customer_profiles(customer_id uuid primary key, user_id uuid,
      service_preferences text[]);
    create table public.service_categories(category_id uuid primary key,
      category_name text, is_active boolean);
    create table public.provider_profiles(provider_id uuid primary key,user_id uuid,
      business_name text,overall_rating numeric,total_reviews integer,verification_status text);
    create table public.services(service_id uuid primary key,provider_id uuid,category_id uuid,
      service_name text,base_price numeric,pricing_type text,is_active boolean,availability_status boolean);
    create table public.bookings(provider_id uuid,booking_status text);
    create table storage.objects(bucket_id text,name text,owner_id text);
    create function auth.uid() returns uuid language sql as
      $$select nullif(current_setting('test.uid',true),'')::uuid$$;
    create function private.customer_viewer_user_id() returns uuid language sql as
      $$select user_id from public.customer_profiles where user_id=auth.uid()$$;
    create function private.customer_id() returns uuid language plpgsql as $$
      declare cid uuid; begin
        select c.customer_id into cid from public.customer_profiles c join public.users u using(user_id)
        where u.user_id=auth.uid() and u.is_active;
        if cid is null then raise exception 'Active customer required' using errcode='42501'; end if;
        return cid;
      end$$;
    insert into public.users values('00000000-0000-4000-8000-000000000001','Customer',null,null,true);
    insert into public.customer_profiles values('00000000-0000-4000-8000-000000000002',
      '00000000-0000-4000-8000-000000000001','{}');
    select set_config('test.uid','00000000-0000-4000-8000-000000000001',false);
    insert into public.service_categories values
      ('10000000-0000-4000-8000-000000000001','Electrical',true),
      ('10000000-0000-4000-8000-000000000002','Plumbing',true),
      ('10000000-0000-4000-8000-000000000003','Retired',false),
      ('10000000-0000-4000-8000-000000000004','No providers',true);
    do $$declare uid uuid; pid uuid; i integer; begin
      for i in 1..8 loop
        uid:=gen_random_uuid(); pid:=gen_random_uuid();
        insert into public.users(user_id,is_active) values(uid,true);
        insert into public.provider_profiles values(pid,uid,'Provider '||i,6-i*.1,10,'Verified');
        insert into public.services values(gen_random_uuid(),pid,'10000000-0000-4000-8000-000000000001',
          'Electrical '||i,10,'Fixed',true,true);
        if i=8 then
          insert into public.services values(gen_random_uuid(),pid,'10000000-0000-4000-8000-000000000002',
            'Preferred plumbing',100,'Hourly',true,true);
        end if;
      end loop;
    end$$;
  `);
  await db.exec(readFileSync(join(__dirname, '../migrations/20261106062433_customer_explore_preferences.sql'), 'utf8'));
  const save = (preferences) => db.query(
    "select private.customer_profile_update('Customer', '+60123456789', $1::text[])", [preferences]);
  const directory = async () => (await db.query('select private.customer_provider_directory() as result')).rows[0].result;
  await t.test('saving retains first selection order and deduplicates normalized names', async () => {
    await save([' Plumbing ', 'Electrical', 'plumbing']);
    assert.deepEqual((await db.query('select service_preferences from customer_profiles')).rows[0].service_preferences,
      ['Plumbing', 'Electrical']);
  });
  await t.test('match happens before limit and representative service follows priority', async () => {
    const rows = await directory();
    assert.equal(rows.length, 5);
    assert.equal(rows[0].business_name, 'Provider 8');
    assert.equal(rows[0].service_name, 'Preferred plumbing');
    assert.equal(rows[0].pricing_type, 'Hourly');
    assert.equal(new Set(rows.map(r => r.provider_id)).size, 5);
    await save(['Electrical', 'Plumbing']);
    assert.equal((await directory())[0].business_name, 'Provider 1');
  });
  await t.test('one preference excludes unrelated services and unavailable providers', async () => {
    await save(['Plumbing']);
    assert.equal((await directory()).length, 1);
    await db.exec("update provider_profiles set verification_status='Pending' where business_name='Provider 8'");
    assert.deepEqual(await directory(), []);
    await db.exec("update provider_profiles set verification_status='Verified'; update services set availability_status=false where service_name='Preferred plumbing'");
    assert.deepEqual(await directory(), []);
    await db.exec('update services set availability_status=true');
    await save(['No providers']);
    assert.deepEqual(await directory(), []);
  });
  await t.test('empty or retired preferences fall back to rated directory', async () => {
    for (const preferences of [[], ['Retired'], ['Missing']]) {
      await save(preferences);
      const rows = await directory();
      assert.equal(rows.length, 5);
      assert.equal(rows[0].business_name, 'Provider 1');
    }
  });
  await t.test('validation and suspended-viewer boundaries remain intact', async () => {
    await assert.rejects(save(Array(21).fill('Electrical')), /valid personal details/);
    await db.exec("update users set is_active=false where user_id=auth.uid()");
    assert.equal((await directory()).length, 5);
    await assert.rejects(save(['Plumbing']), /Active customer required/);
    await db.exec("select set_config('test.uid','',false)");
    await assert.rejects(directory(), /verified customer account/);
  });
});
