import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { handleCheckout, handleWebhook, handleReturn, verifyStripeSignature } from '../functions/_shared/fpx.ts';

const now = Date.UTC(2026, 9, 2, 9);
const booking = '11111111-1111-4111-8111-111111111111';
const attempt = '22222222-2222-4222-8222-222222222222';
const expires = Math.floor(now / 1000) + 1860;
const env = { SUPABASE_URL: 'https://project.invalid', SUPABASE_ANON_KEY: 'anon-fixture', SUPABASE_SERVICE_ROLE_KEY: 'service-fixture', STRIPE_SECRET_KEY: 'sk_test_fixture', STRIPE_WEBHOOK_SECRET: 'whsec_fixture' };
const json = data => new Response(JSON.stringify(data), { headers: { 'Content-Type': 'application/json' } });
const quote = { attempt_id: attempt, amount_sen: 18000, service_name: 'Cleaning', expires_at: new Date(expires * 1000).toISOString(), state: 'Creating' };
const session = { id: 'cs_test_fixture', url: 'https://checkout.stripe.com/c/pay/cs_test_fixture', livemode: false, mode: 'payment', amount_total: 18000, currency: 'myr', expires_at: expires, payment_status: 'paid', payment_intent: 'pi_fixture', metadata: { attempt_id: attempt } };
function deps(fetch, overrides = {}) { return { env: name => ({ ...env, ...overrides })[name], now: () => now, fetch }; }
function checkout(body = { booking_id: booking }, authorization = 'Bearer customer-fixture') { return new Request('https://project.invalid/checkout', { method: 'POST', headers: { Authorization: authorization }, body: JSON.stringify(body) }); }
function signature(body, timestamp = Math.floor(now / 1000)) { return `t=${timestamp},v1=${createHmac('sha256', env.STRIPE_WEBHOOK_SECRET).update(`${timestamp}.${body}`).digest('hex')}`; }
function event(overrides = {}) { return { id: 'evt_fixture', livemode: false, type: 'checkout.session.completed', data: { object: session }, ...overrides }; }
function webhook(data, signed = true) { const body = JSON.stringify(data); return new Request('https://project.invalid/webhook', { method: 'POST', headers: signed ? { 'Stripe-Signature': signature(body) } : {}, body }); }
const noNetwork = async () => { throw new Error('Unexpected network call'); };

test('unauthenticated checkout is rejected before network calls', async () => assert.equal((await handleCheckout(checkout({}, ''), deps(noNetwork))).status, 401));
test('price injection is rejected before quote or Stripe calls', async () => {
  let calls = 0;
  const response = await handleCheckout(checkout({ booking_id: booking, amount: 1 }), deps(async () => { calls++; return json({ id: 'customer' }); }));
  assert.equal(response.status, 400); assert.equal(calls, 1);
});
test('live secret keys fail closed', async () => assert.equal((await handleCheckout(checkout(), deps(async () => json({ id: 'customer' }), { STRIPE_SECRET_KEY: 'sk_live_fixture' }))).status, 503));
test('missing test configuration never fabricates a checkout', async () => assert.equal((await handleCheckout(checkout(), deps(async () => json({ id: 'customer' }), { STRIPE_SECRET_KEY: undefined }))).status, 503));
test('checkout uses server amount, stable idempotency parameters and signed return', async () => {
  const forms = []; let attached = 0;
  const dependencies = deps(async (url, options) => {
    if (url.endsWith('/auth/v1/user')) return json({ id: 'customer' });
    if (url.endsWith('/customer_prepare_checkout')) return json(quote);
    if (url.includes('api.stripe.com')) {
      assert.equal(options.headers['Idempotency-Key'], `fyp-fpx-${attempt}`);
      const form = options.body; forms.push(form.toString());
      assert.equal(form.get('line_items[0][price_data][unit_amount]'), '18000');
      assert.equal(form.get('payment_method_types[0]'), 'fpx');
      assert.equal((await handleReturn(new Request(form.get('success_url')), deps(noNetwork))).status, 200);
      return json(session);
    }
    assert.ok(url.endsWith('/gateway_attach_checkout')); attached++;
    assert.equal(options.headers.Authorization, 'Bearer service-fixture');
    return new Response(null, { status: 204 });
  });
  assert.equal((await handleCheckout(checkout(), dependencies)).status, 200);
  dependencies.now = () => now + 30000;
  assert.equal((await handleCheckout(checkout(), dependencies)).status, 200);
  assert.equal(forms[0], forms[1]); assert.equal(attached, 2);
});
test('an open checkout reuses its hosted URL without another Stripe session', async () => {
  let calls = 0;
  const response = await handleCheckout(checkout(), deps(async url => { calls++; return json(url.endsWith('/user') ? { id: 'customer' } : { ...quote, state: 'Open', checkout_url: session.url, gateway_session_id: session.id }); }));
  assert.equal(response.status, 200); assert.equal(calls, 2);
});
test('checkout rejects a redirect outside Stripe', async () => {
  const response = await handleCheckout(checkout(), deps(async url => json(url.endsWith('/user') ? { id: 'customer' } : { ...quote, state: 'Open', checkout_url: 'https://evil.invalid/' })));
  assert.equal(response.status, 502);
});
test('webhook signature rejects modified body, expired signature and wrong secret', async () => {
  const body = JSON.stringify(event());
  assert.equal(await verifyStripeSignature(body, signature(body), env.STRIPE_WEBHOOK_SECRET, now), true);
  assert.equal(await verifyStripeSignature(`${body} `, signature(body), env.STRIPE_WEBHOOK_SECRET, now), false);
  assert.equal(await verifyStripeSignature(body, signature(body, now / 1000 - 301), env.STRIPE_WEBHOOK_SECRET, now), false);
  assert.equal(await verifyStripeSignature(body, signature(body), 'different', now), false);
});
test('unsigned callback cannot mutate the database', async () => assert.equal((await handleWebhook(webhook(event(), false), deps(noNetwork))).status, 400));
test('live callback is rejected even with valid signature', async () => assert.equal((await handleWebhook(webhook(event({ livemode: true })), deps(noNetwork))).status, 400));
test('checkout completion with unpaid status does not record payment', async () => {
  const response = await handleWebhook(webhook(event({ data: { object: { ...session, payment_status: 'unpaid' } } })), deps(noNetwork));
  assert.equal(response.status, 200); assert.equal((await response.json()).awaiting_payment, true);
});
test('verified callback forwards exact identity, amount and reference to privileged RPC', async () => {
  let calls = 0;
  const response = await handleWebhook(webhook(event()), deps(async (url, options) => {
    calls++; assert.ok(url.endsWith('/gateway_record_payment'));
    assert.deepEqual(JSON.parse(options.body), { p_event_id: 'evt_fixture', p_attempt_id: attempt, p_session_id: 'cs_test_fixture', p_amount_sen: 18000, p_currency: 'myr', p_outcome: 'paid', p_reference: 'pi_fixture' });
    return json({ recorded: true });
  }));
  assert.equal(response.status, 200); assert.equal(calls, 1);
});
test('database failure asks Stripe to retry instead of losing the payment', async () => {
  const response = await handleWebhook(webhook(event()), deps(async () => new Response('unavailable', { status: 503 })));
  assert.equal(response.status, 503);
});
test('return page cannot assert success and rejects forged links', async () => assert.equal((await handleReturn(new Request('https://project.invalid/payment-return?v=forged&sig=abc'), deps(noNetwork))).status, 400));
test('oversized callback is rejected', async () => {
  const request = new Request('https://project.invalid/webhook', { method: 'POST', body: 'a'.repeat(262145) });
  assert.equal((await handleWebhook(request, deps(noNetwork))).status, 413);
});
for (const [status, release] of [[400, true], [500, false], [429, false]]) {
  test(`Stripe HTTP ${status} ${release ? 'releases' : 'preserves'} checkout attempt safely`, async () => {
    let released = false;
    const response = await handleCheckout(checkout(), deps(async url => {
      if (url.endsWith('/user')) return json({ id: 'customer' });
      if (url.endsWith('/customer_prepare_checkout')) return json(quote);
      if (url.includes('api.stripe.com')) return new Response('{}', { status });
      assert.ok(url.endsWith('/gateway_reject_checkout')); released = true;
      return new Response(null, { status: 204 });
    }));
    assert.equal(response.status, 502); assert.equal(released, release);
  });
}
