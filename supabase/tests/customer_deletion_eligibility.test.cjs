const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync, readdirSync} = require('node:fs');
const {join} = require('node:path');
const {PGlite} = require('@electric-sql/pglite');
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

test('account deletion evaluates actual outstanding obligations', async t => {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec(`
    create schema private; create schema auth;
    create role anon; create role authenticated; create role service_role;
    create table auth.users(id uuid primary key, email_confirmed_at timestamptz);
    create table public.users(user_id uuid primary key, auth_user_id uuid, role text,
      is_active boolean, email text, phone text, password_hash text, full_name text,
      profile_photo_url text, email_verified boolean, phone_verified boolean, last_login_at timestamptz);
    create table customer_profiles(customer_id uuid primary key,user_id uuid,
      default_address text,location_coordinates text,service_preferences text[],bio text,gender text,birthday date);
    create table bookings(booking_id uuid primary key,customer_id uuid,booking_status text,
      reservation_expires_at timestamptz,scheduled_datetime timestamptz,
      customer_address text,customer_coordinates text,special_instructions text,
      request_id uuid default gen_random_uuid(),provider_id uuid default gen_random_uuid(),
      service_id uuid default gen_random_uuid(),total_amount numeric default 50,
      duration_minutes int default 60,accepted_at timestamptz);
    create table payments(payment_id uuid primary key,booking_id uuid,payment_status text);
    create table booking_disputes(booking_id uuid,status text,opened_by uuid);
    create table refund_requests(payment_id uuid,status text);
    create table private.checkout_attempts(booking_id uuid,state text,expires_at timestamptz);
    create table private.customer_deletions(auth_user_id uuid primary key,user_id uuid unique,completed_at timestamptz);
    create table saved_addresses(customer_id uuid);
    create table private.notification_outbox(recipient_user_id uuid);
    create table notifications(user_id uuid);
    create table otp_verifications(user_id uuid);
    create table reviews(customer_id uuid,review_comment text,review_image_url text);
    create table chat_messages(sender_id uuid,body text);
    create table chat_members(user_id uuid,hidden boolean,blocked boolean);
  `);
  const dir = join(__dirname, '../migrations');
  await db.exec(readFileSync(join(dir, readdirSync(dir).find(f => f.endsWith('_customer_deletion_eligibility.sql'))), 'utf8'));
  // Install the real booking trigger, including non-null app request tokens.
  // The previous fixture omitted it and incorrectly passed anonymization.
  const source = readFileSync(join(dir, '20261002080447_customer_module_integration.sql'), 'utf8');
  const guard = source.slice(source.indexOf('create function private.guard_customer_booking()'), source.indexOf('create function public.customer_create_booking('));
  await db.exec(guard);
  const seed = `
    insert into auth.users values('${id(1)}',now());
    insert into public.users(user_id,auth_user_id,role,is_active,email,full_name) values('${id(1)}','${id(1)}','customer',true,'test@example.invalid','Test');
    insert into customer_profiles(customer_id,user_id) values('${id(2)}','${id(1)}');
    insert into bookings(booking_id,customer_id,booking_status,reservation_expires_at,scheduled_datetime,customer_address,customer_coordinates,special_instructions)
      values('${id(3)}','${id(2)}','Cancelled',now()-interval '1 day',now()+interval '1 day','Private address','Coordinates','Private instructions');
  `;
  await t.test('reproduces the old trigger conflict for an app-created cancelled booking', async () => {
    await db.exec(`begin; ${seed} savepoint deletion;`);
    await assert.rejects(db.query('select private.customer_delete_prepare($1)', [id(1)]), /agreed service, price, address and time/);
    await db.exec('rollback to deletion');
    assert.equal((await db.query('select is_active from public.users')).rows[0].is_active, true);
    await db.exec('rollback');
  });
  await db.exec(readFileSync(join(dir, readdirSync(dir).find(f => f.endsWith('_customer_deletion_booking_anonymization.sql'))), 'utf8'));
  const policy = readFileSync(join(dir,readdirSync(dir).find(f=>f.endsWith('_customer_support_deletion_and_cooldown_display.sql'))),'utf8');
  await db.exec(policy.split('-- Return only')[0]);
  const cases = [
    ['cancelled, never paid', 'Cancelled', null, 'future', 'future', null],
    ['expired pending reservation', 'Pending', null, 'past', 'future', null],
    ['expired confirmed reservation', 'Confirmed', null, 'past', 'future', null],
    ['unpaid appointment already passed', 'Confirmed', null, null, 'past', null],
    ['deadline exactly now', 'Pending', null, 'boundary', 'future', null],
    ['failed payment on expired booking', 'Confirmed', 'Failed', 'past', 'past', null],
    ['completed paid booking', 'Completed', 'Success', null, 'past', null],
    ['cancelled refunded booking', 'Cancelled', 'Refunded', 'past', 'past', null],
    ['future unpaid pending booking', 'Pending', null, 'future', 'future', /active bookings/],
    ['future unpaid confirmed booking', 'Confirmed', null, 'future', 'future', /active bookings/],
    ['legacy booking with unknown dates', 'Pending', null, null, null, /active bookings/],
    ['paid confirmed appointment already passed', 'Confirmed', 'Success', 'past', 'past', /active bookings/],
    ['in-progress work despite old date', 'In-Progress', null, 'past', 'past', /active bookings/],
    ['pending payment on cancelled booking', 'Cancelled', 'Pending', 'past', 'past', /payment is still being verified/],
  ];
  for (const status of ['Open', 'Under Review', 'Resolved']) {
    cases.push([`dispute ${status}`, 'Cancelled', 'Success', 'past', 'past', status === 'Resolved' ? null : /dispute is still open/, `insert into booking_disputes values('${id(3)}','${status}','${id(1)}')`]);
  }
  for (const status of ['Open','Under Review']) {
    for (const booking of ['Cancelled','Pending','Confirmed']) {
      cases.push([`own unpaid ${booking} support ${status}`,booking,null,'past','past',null,
        `insert into booking_disputes values('${id(3)}','${status}','${id(1)}')`]);
    }
    cases.push([`another party's unpaid dispute ${status}`,'Cancelled',null,'past','past',/dispute is still open/,
      `insert into booking_disputes values('${id(3)}','${status}','${id(99)}')`]);
    cases.push([`unattributed unpaid dispute ${status}`,'Cancelled',null,'past','past',/dispute is still open/,
      `insert into booking_disputes values('${id(3)}','${status}',null)`]);
    cases.push([`refunded dispute ${status}`,'Cancelled','Refunded','past','past',/dispute is still open/,
      `insert into booking_disputes values('${id(3)}','${status}','${id(1)}')`]);
    cases.push([`open gateway on unpaid support ${status}`,'Cancelled',null,'past','past',/dispute is still open/,
      `insert into booking_disputes values('${id(3)}','${status}','${id(1)}'); insert into private.checkout_attempts values('${id(3)}','Open',now())`]);
  }
  for (const state of ['Creating', 'Open', 'Expired', 'Failed', 'Paid']) {
    cases.push([`checkout ${state} with elapsed deadline`, 'Cancelled', null, 'past', 'past', ['Creating','Open'].includes(state) ? /payment is still being verified/ : null, `insert into private.checkout_attempts values('${id(3)}','${state}',now()-interval '1 day')`]);
  }
  for (const status of ['Requested', 'Processing', 'Succeeded', 'Failed']) {
    cases.push([`refund ${status}`, 'Cancelled', 'Success', 'past', 'past', ['Requested','Processing'].includes(status) ? /refund is still pending/ : null, `insert into refund_requests values('${id(4)}','${status}')`]);
  }
  const date = value => value === 'past' ? "now()-interval '1 day'" : value === 'future' ? "now()+interval '1 day'" : value === 'boundary' ? 'now()' : 'null';
  for (const [name, status, payment, deadline, appointment, error, extra] of cases) {
    await t.test(name, async () => {
      await db.exec(`begin;
        insert into auth.users values('${id(1)}',now());
        insert into public.users(user_id,auth_user_id,role,is_active,email,full_name) values('${id(1)}','${id(1)}','customer',true,'test@example.invalid','Test');
        insert into customer_profiles(customer_id,user_id) values('${id(2)}','${id(1)}');
        insert into bookings(booking_id,customer_id,booking_status,reservation_expires_at,scheduled_datetime,customer_address,customer_coordinates,special_instructions)
          values('${id(3)}','${id(2)}','${status}',${date(deadline)},${date(appointment)},'Private address','Coordinates','Private instructions');
        ${payment ? `insert into payments values('${id(4)}','${id(3)}','${payment}');` : ''}
        ${extra || ''};
        savepoint deletion;
      `);
      try {
        const call = () => db.query('select private.customer_delete_prepare($1) result', [id(1)]);
        if (error) {
          await assert.rejects(call(), error);
          await db.exec('rollback to deletion');
          assert.equal((await db.query('select is_active from public.users')).rows[0].is_active, true);
          assert.equal((await db.query('select count(*)::int n from private.customer_deletions')).rows[0].n, 0);
        } else {
          assert.equal((await call()).rows[0].result.prepared, true);
          assert.equal((await db.query('select auth_user_id from public.users')).rows[0].auth_user_id, null);
          assert.equal((await db.query('select customer_address from bookings')).rows[0].customer_address, 'Deleted customer');
          assert.deepEqual((await db.query('select customer_coordinates,special_instructions from bookings')).rows[0], {customer_coordinates:null,special_instructions:null});
          assert.equal((await call()).rows[0].result.prepared, true, 'retry remains idempotent');
        }
      } finally {
        await db.exec('rollback');
      }
    });
  }
  for (const setup of ['', `insert into private.customer_deletions(auth_user_id,user_id) values('${id(1)}','${id(1)}');`, 'update public.users set auth_user_id=null,is_active=false;']) {
    await t.test(`address scrubbing requires both deletion marker and detached identity: ${setup || 'neither'}`, async () => {
      await db.exec(`begin; ${seed} ${setup}`);
      await assert.rejects(db.exec("update bookings set customer_address='Deleted customer',customer_coordinates=null,special_instructions=null"), /agreed service/);
      await db.exec('rollback');
    });
  }
  for (const mutation of ["total_amount=1", "scheduled_datetime=now()+interval '3 days'", "booking_status='Confirmed'", 'request_id=null', 'request_id=gen_random_uuid()', 'service_id=gen_random_uuid()', 'provider_id=gen_random_uuid()', 'customer_id=gen_random_uuid()', "customer_address='Different address'"]) {
    await t.test(`deletion exception cannot change booking contract: ${mutation}`, async () => {
      await db.exec(`begin; ${seed}
        insert into private.customer_deletions(auth_user_id,user_id) values('${id(1)}','${id(1)}');
        update public.users set auth_user_id=null,is_active=false;
      `);
      const address = mutation.startsWith('customer_address') ? '' : "customer_address='Deleted customer',";
      await assert.rejects(db.exec(`update bookings set ${address}customer_coordinates=null,special_instructions=null,${mutation}`), /agreed service/);
      await db.exec('rollback');
    });
  }
  await t.test('only the trusted deletion service can prepare deletion', async () => {
    for (const role of ['anon', 'authenticated', 'service_role']) {
      const result = await db.query(`select has_function_privilege('${role}','private.customer_delete_prepare(uuid)','execute') allowed`);
      assert.equal(result.rows[0].allowed, role === 'service_role');
    }
    await assert.rejects(db.query('select private.customer_delete_prepare(null)'), /Sign in again/);
    await assert.rejects(db.query('select private.customer_delete_prepare($1)', [id(99)]), /active verified customer/);
  });
});
