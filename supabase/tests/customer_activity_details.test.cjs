const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync, readdirSync} = require('node:fs');
const {join} = require('node:path');
const {PGlite} = require('@electric-sql/pglite');

test('customer activity events execute in PostgreSQL', async t => {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec(`
    create schema private; create schema auth;
    create role anon; create role authenticated;
    create table users(user_id uuid primary key default gen_random_uuid(), auth_user_id uuid,
      role text default 'customer',is_active boolean default true,full_name text,phone text,email text,profile_photo_url text);
    create table customer_profiles(customer_id uuid primary key default gen_random_uuid(),user_id uuid,
      bio text,gender text,birthday date,service_preferences text[]);
    create table saved_addresses(customer_id uuid,label text,address_line text,city text,state text,postcode text,coordinates text,is_default boolean);
    create table auth.users(id uuid,encrypted_password text);
    create table notifications(notification_id uuid primary key default gen_random_uuid(),user_id uuid,booking_id uuid,
      notification_type text,title varchar(200),message varchar(500));
    create table private.notification_outbox(notification_id uuid,recipient_user_id uuid);
    create function private.admin_actor() returns uuid language plpgsql as $$begin
      if current_setting('test.admin',true) is distinct from 'true' then raise exception 'Admin required' using errcode='42501'; end if;
      return '00000000-0000-4000-8000-000000000002'::uuid;
    end$$;
    insert into users(user_id,auth_user_id,full_name) values('00000000-0000-4000-8000-000000000001',gen_random_uuid(),'Before');
    insert into customer_profiles(user_id,service_preferences) select user_id,array['Plumbing','Electrical'] from users;
    insert into saved_addresses(customer_id,label,city,is_default) select customer_id,'Home','City',false from customer_profiles;
    insert into auth.users select auth_user_id,'oldhash' from users;
  `);
  const dir = join(__dirname,'../migrations');
  const migration = readdirSync(dir).find(f=>f.endsWith('_customer_activity_details.sql'));
  await db.exec(readFileSync(join(dir,migration),'utf8'));
  await db.exec(`
    create trigger identity_activity after update on users for each row execute function private.customer_activity();
    create trigger profile_activity after update on customer_profiles for each row execute function private.customer_activity();
    create trigger address_activity after insert or update or delete on saved_addresses for each row execute function private.customer_activity();
    create trigger password_activity after update on auth.users for each row execute function private.customer_activity();
  `);
  const messages = async ()=>(await db.query('select * from notifications')).rows;
  const clear = ()=>db.exec('delete from notifications');
  await t.test('name-only update identifies only name and no-op produces no event', async()=>{
    await db.exec("update users set full_name='Sensitive name'");
    const rows=await messages(); assert.equal(rows.length,1);
    assert.equal(rows[0].message,'Your name was updated.');
    assert.equal(rows[0].event_key,'customer.activity');
    await clear(); await db.exec('update users set full_name=full_name');
    assert.equal((await messages()).length,0);
  });
  await t.test('multiple profile changes include each field without personal values', async()=>{
    await db.exec("update customer_profiles set bio='Sensitive bio',gender='Male',birthday='1990-01-01'");
    assert.equal((await messages())[0].message,'Your bio was updated.\nYour gender was updated.\nYour birthday was updated.');
    await clear(); await db.exec('update customer_profiles set bio=null');
    assert.equal((await messages())[0].message,'Your bio was updated.'); await clear();
  });
  await t.test('preference reorder, membership change, clear and empty no-op are distinguished', async()=>{
    for(const [values,expected] of [
      ["array['Electrical','Plumbing']",'Your preferred service order was updated.'],
      ["array['Electrical']",'Your service selection was updated. Explore now follows your preferences.'],
      ["'{}'",'Your service preferences were cleared. Explore now shows every service.']]) {
      await db.exec(`update customer_profiles set service_preferences=${values}`);
      assert.equal((await messages())[0].message,expected); await clear();
    }
    await db.exec('update customer_profiles set service_preferences=null');
    assert.equal((await messages()).length,0);
  });
  await t.test('address changes preserve all changed fields including default selection', async()=>{
    await db.exec("update saved_addresses set city='Private city',is_default=true");
    assert.equal((await messages())[0].message,'This address is now your default service address.\nYour address city was updated.');
    await clear();
  });
  await t.test('password event never includes password or hash', async()=>{
    await db.exec("update auth.users set encrypted_password='secrethash'");
    assert.match((await messages())[0].message,/Your account password was changed/);
    assert.ok(!(await messages())[0].message.includes('secrethash')); await clear();
  });
  await t.test('inactive customers and providers do not receive customer profile activity', async()=>{
    await db.exec("update users set is_active=false,full_name='Inactive'; update customer_profiles set bio='Hidden'");
    assert.equal((await messages()).length,0);
    await db.exec("update users set is_active=true,role='provider',full_name='Provider'");
    assert.equal((await messages()).length,0);
    await db.exec("update users set role='customer'");
  });
  await t.test('admin guard, suspension and reactivation retain reason and outbox delivery', async()=>{
    const notify = "select private.admin_notify('00000000-0000-4000-8000-000000000001','Account status updated','Review reason')";
    await assert.rejects(db.exec(notify),/Admin required/);
    await db.exec("select set_config('test.admin','true',false); update users set is_active=false");
    await db.exec(notify);
    assert.equal((await messages())[0].event_key,'account.suspended');
    assert.equal((await messages())[0].title,'Account suspended');
    assert.equal((await messages())[0].message,'Review reason');
    await db.exec('update users set is_active=true'); await db.exec(notify);
    assert.deepEqual((await messages()).map(r=>r.event_key),['account.suspended','account.reactivated']);
    assert.equal((await db.query('select count(*)::int n from private.notification_outbox')).rows[0].n,2);
    const grants=(await db.query("select has_function_privilege('authenticated','private.admin_notify(uuid,text,text,uuid)','execute') allowed")).rows[0];
    assert.equal(grants.allowed,false);
  });
});
