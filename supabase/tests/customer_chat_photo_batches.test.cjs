// Isolated PostgreSQL. The photo sender fixture stands in for the existing
// storage and messaging RPC, allowing the batch transaction to be exercised.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { PGlite } = require('@electric-sql/pglite');

const migration = name => readFileSync(join(__dirname, '../migrations', name), 'utf8');
test('photo turns retain every path and provider batches commit together', async t => {
  const db = new PGlite();
  t.after(() => db.close());
  const uid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const cid = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  const rid = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  const paths = Array.from({length: 5}, (_,i) => `${uid}/${cid}/${rid.slice(0,-1)}${i}.jpg`);
  await db.exec(`
    create role anon; create role authenticated;
    create schema private; create schema storage;
    create table customer_profiles(customer_id uuid primary key);
    create table storage.objects(bucket_id text, name text);
    create function private.customer_id() returns uuid language sql as $$select '${uid}'::uuid$$;
    create function private.chat_actor() returns uuid language sql as $$select '${uid}'::uuid$$;
    create table chat_messages(message_id bigserial primary key, attachment_path text unique);
    create function private.chat_send_photo(uuid,text,uuid) returns jsonb language plpgsql as $$
    declare mid bigint;
    begin
      if not exists(select from storage.objects where name=$2) then raise exception 'Missing upload'; end if;
      insert into public.chat_messages(attachment_path) values($2) on conflict(attachment_path) do update
        set attachment_path=excluded.attachment_path returning message_id into mid;
      return jsonb_build_object('message_id',mid);
    end $$;
  `);
  const initial = migration('20261013030453_customer_gemini_assistant.sql');
  await db.exec(initial.slice(0,initial.indexOf('create function private.customer_ai_create_conversation')));
  await db.exec(initial.slice(initial.indexOf('create function private.customer_ai_begin_turn'),initial.indexOf('create function private.ai_finish_turn')));
  await db.exec("alter table private.ai_messages add column origin text default 'chat', add column agent_event_kind text");
  await db.exec(migration('20261128000000_customer_ai_photo_messages.sql'));
  await db.exec(migration('20261128000001_provider_chat_photo_batch.sql'));
  await db.query('insert into customer_profiles values ($1)',[uid]);
  await db.query('insert into private.ai_conversations(id,auth_id,customer_id,request_id) values($1,$2,$2,$3)',[cid,uid,rid]);
  await db.query("insert into storage.objects select 'customer-ai-images', unnest($1::text[])",[paths]);
  const ai = photos => db.query("select public.customer_ai_begin_photo_turn($1,$2,'',$3,'chat') as result",[cid,rid,photos]);
  const sent = await ai(paths);
  assert.deepEqual(sent.rows[0].result.history[0].image_paths,paths);
  await db.exec("update private.ai_turns set status='failed'");
  await assert.rejects(ai([...paths].reverse()));
  assert.deepEqual((await ai(paths)).rows[0].result.history[0].image_paths,paths);
  const provider = photos => db.query("select public.chat_send_photos($1,$2,'Please check these') as result",[cid,photos]);
  await assert.rejects(provider([...paths,paths[0]]));
  await assert.rejects(provider([paths[0],paths[1].replace('.jpg','.png')]));
  assert.equal((await db.query('select count(*)::int n from chat_messages')).rows[0].n,0);
  assert.equal((await provider(paths)).rows[0].result.at(-1).photo_caption,'Please check these');
  await provider(paths);
  assert.equal((await db.query('select count(*)::int n from chat_messages')).rows[0].n,5);
});
