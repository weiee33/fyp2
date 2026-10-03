type Dependencies = { env: (name: string) => string | undefined; fetch: typeof fetch; now: () => number };
class HttpError extends Error {
  status: number;
  constructor(status: number, message: string) { super(message); this.status = status; }
}
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function required(deps: Dependencies, name: string): string {
  const value = deps.env(name);
  if (!value) throw new HttpError(503, 'FPX test checkout is not configured yet. Please contact the project owner.');
  return value;
}
async function boundedBody(request: Request, maximum: number): Promise<string> {
  const reader = request.body?.getReader();
  if (!reader) return '';
  const decoder = new TextDecoder(); let size = 0; let text = '';
  try {
    while (true) {
      const { done, value } = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > maximum) { await reader.cancel(); throw new HttpError(413, 'Request too large'); }
      text += decoder.decode(value, { stream: true });
    }
    return text + decoder.decode();
  } finally { reader.releaseLock(); }
}
async function rpc(deps: Dependencies, name: string, params: unknown, token: string, key: string): Promise<any> {
  const response = await deps.fetch(`${required(deps, 'SUPABASE_URL')}/rest/v1/rpc/${name}`, {
    method: 'POST', headers: { apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(params), signal: AbortSignal.timeout(20000),
  });
  const raw = await response.text();
  const body = raw === '' ? null : JSON.parse(raw);
  if (!response.ok) {
    const message = ['P0001', '42501', '23P01'].includes(body?.code) && typeof body?.message === 'string'
      ? body.message : 'The payment operation could not complete. Please retry.';
    throw new HttpError(response.status === 403 ? 403 : 409, message);
  }
  return body;
}
function checkoutUrl(value: unknown): string {
  if (typeof value !== 'string') throw new HttpError(502, 'Invalid checkout response');
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.hostname !== 'checkout.stripe.com' || url.username || url.password || (url.port && url.port !== '443')) throw new HttpError(502, 'Invalid checkout response');
  return url.toString();
}
export async function handleCheckout(request: Request, deps: Dependencies): Promise<Response> {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (request.method !== 'POST') return json({ error: 'Use POST' }, 405);
  try {
    const authorization = request.headers.get('Authorization') ?? '';
    if (!/^Bearer \S+$/.test(authorization)) throw new HttpError(401, 'Please sign in.');
    const token = authorization.substring(7);
    const apiKey = required(deps, 'SUPABASE_ANON_KEY');
    const userResponse = await deps.fetch(`${required(deps, 'SUPABASE_URL')}/auth/v1/user`, { headers: { apikey: apiKey, Authorization: authorization }, signal: AbortSignal.timeout(15000) });
    if (!userResponse.ok) throw new HttpError(401, 'Please sign in again.');
    let input: any;
    try { input = JSON.parse(await boundedBody(request, 8192)); } catch (e) { if (e instanceof HttpError) throw e; throw new HttpError(400, 'Invalid checkout request'); }
    if (!uuid.test(input?.booking_id ?? '') || Object.keys(input).some(key => key !== 'booking_id')) throw new HttpError(400, 'Only the booking ID is accepted; prices are calculated by the server.');
    const stripeKey = required(deps, 'STRIPE_SECRET_KEY');
    if (!stripeKey.startsWith('sk_test_')) throw new HttpError(503, 'This FYP gateway requires a Stripe test key. Live payments are disabled.');
    const serviceKey = required(deps, 'SUPABASE_SERVICE_ROLE_KEY');
    const attempt = await rpc(deps, 'customer_prepare_checkout', { p_booking_id: input.booking_id }, token, apiKey);
    if (attempt.state === 'Open' && attempt.checkout_url) return json({ checkout_url: checkoutUrl(attempt.checkout_url), session_id: attempt.gateway_session_id, expires_at: attempt.expires_at, test_mode: true });
    if (!uuid.test(attempt.attempt_id) || !Number.isSafeInteger(Number(attempt.amount_sen)) || Number(attempt.amount_sen) <= 0) throw new HttpError(502, 'Invalid checkout quote');
    // Stable parameters are required when retrying a Stripe idempotency key.
    const returnPayload = `${attempt.attempt_id}.${Math.floor(Date.parse(attempt.expires_at) / 1000) + 3600}`;
    const returnSignature = await signReturn(returnPayload, serviceKey);
    const returnUrl = `${required(deps, 'SUPABASE_URL')}/functions/v1/payment-return?v=${returnPayload}&sig=${returnSignature}`;
    const form = new URLSearchParams({ mode: 'payment', 'payment_method_types[0]': 'fpx',
      'line_items[0][price_data][currency]': 'myr', 'line_items[0][price_data][unit_amount]': String(attempt.amount_sen),
      'line_items[0][price_data][product_data][name]': String(attempt.service_name || 'Local Life service'), 'line_items[0][quantity]': '1',
      client_reference_id: attempt.attempt_id, 'metadata[attempt_id]': attempt.attempt_id, 'metadata[booking_id]': input.booking_id,
      expires_at: String(Math.floor(Date.parse(attempt.expires_at) / 1000)), success_url: returnUrl, cancel_url: returnUrl,
    });
    const response = await deps.fetch('https://api.stripe.com/v1/checkout/sessions', { method: 'POST',
      headers: { Authorization: `Bearer ${stripeKey}`, 'Stripe-Version': '2025-02-24.acacia', 'Idempotency-Key': `fyp-fpx-${attempt.attempt_id}`, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: form, signal: AbortSignal.timeout(20000),
    });
    if (!response.ok) {
      if ([400, 401, 402, 403, 404, 422].includes(response.status)) {
        await rpc(deps, 'gateway_reject_checkout', { p_attempt_id: attempt.attempt_id }, serviceKey, serviceKey);
      }
      throw new HttpError(502, 'FPX checkout could not open. Check that FPX is enabled in your Stripe Malaysia test account, then retry.');
    }
    const session = await response.json();
    const url = checkoutUrl(session.url);
    if (session.livemode !== false || !String(session.id).startsWith('cs_test_') || session.currency !== 'myr' || session.amount_total !== Number(attempt.amount_sen)) throw new HttpError(502, 'Gateway checkout did not match the booking quote');
    await rpc(deps, 'gateway_attach_checkout', { p_attempt_id: attempt.attempt_id, p_session_id: session.id, p_checkout_url: url, p_expires_at: new Date(session.expires_at * 1000).toISOString() }, serviceKey, serviceKey);
    return json({ checkout_url: url, session_id: session.id, expires_at: new Date(session.expires_at * 1000).toISOString(), test_mode: true });
  } catch (error) { return json({ error: error instanceof HttpError ? error.message : 'Checkout is temporarily unavailable. Please retry.' }, error instanceof HttpError ? error.status : 503); }
}

export async function verifyStripeSignature(body: string, signature: string, secret: string, now: number): Promise<boolean> {
  const parts = signature.split(',').map(value => value.trim().split('='));
  const timestamp = parts.find(part => part[0] === 't')?.[1] ?? '';
  if (!/^\d+$/.test(timestamp) || Math.abs(now / 1000 - Number(timestamp)) > 300) return false;
  const signatures = parts.filter(part => part[0] === 'v1' && /^[0-9a-f]{64}$/.test(part[1] ?? '')).map(part => part[1]);
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
  for (const value of signatures) {
    const bytes = Uint8Array.from(value.match(/../g)!, pair => parseInt(pair, 16));
    if (await crypto.subtle.verify('HMAC', key, bytes, encoder.encode(`${timestamp}.${body}`))) return true;
  }
  return false;
}
async function signReturn(payload: string, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(`local-life-payment-return\n${payload}`));
  return Array.from(new Uint8Array(signature), value => value.toString(16).padStart(2, '0')).join('');
}
export async function handleReturn(request: Request, deps: Dependencies): Promise<Response> {
  const headers = { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' };
  try {
    const url = new URL(request.url), value = url.searchParams.get('v') ?? '', sig = url.searchParams.get('sig') ?? '';
    const [id, expires] = value.split('.');
    if (!uuid.test(id) || !/^\d+$/.test(expires ?? '') || Number(expires) < deps.now() / 1000 || Number(expires) > deps.now() / 1000 + 7200 || !/^[0-9a-f]{64}$/.test(sig)) throw new Error('Invalid return');
    const expected = await signReturn(value, required(deps, 'SUPABASE_SERVICE_ROLE_KEY'));
    let difference = 0; for (let i = 0; i < expected.length; i++) difference |= expected.charCodeAt(i) ^ sig.charCodeAt(i);
    if (difference !== 0) throw new Error('Invalid return');
    return new Response('Return to the Local Life app and select Check payment status. Your receipt appears only after the gateway confirms payment.', { headers });
  } catch { return new Response('This return link is invalid or expired. Open the Local Life app to check your booking.', { status: 400, headers }); }
}
export async function handleWebhook(request: Request, deps: Dependencies): Promise<Response> {
  if (request.method !== 'POST') return json({ error: 'Use POST' }, 405);
  try {
    const secret = required(deps, 'STRIPE_WEBHOOK_SECRET');
    const body = await boundedBody(request, 262144);
    if (!await verifyStripeSignature(body, request.headers.get('Stripe-Signature') ?? '', secret, deps.now())) return json({ error: 'Invalid signature' }, 400);
    let event: any;
    try { event = JSON.parse(body); } catch { return json({ error: 'Invalid JSON' }, 400); }
    if (event.livemode !== false) return json({ error: 'Live payments are disabled' }, 400);
    const types: Record<string, string> = { 'checkout.session.completed': 'paid', 'checkout.session.async_payment_succeeded': 'paid', 'checkout.session.async_payment_failed': 'failed', 'checkout.session.expired': 'expired' };
    const outcome = types[event.type];
    if (!outcome) return json({ ignored: true });
    const session = event.data?.object;
    if (outcome === 'paid' && session?.payment_status !== 'paid') return json({ awaiting_payment: true });
    if (session?.livemode !== false || session.mode !== 'payment' || !String(session.id).startsWith('cs_test_') || !uuid.test(session.metadata?.attempt_id ?? '') || !Number.isSafeInteger(session.amount_total)) return json({ error: 'Invalid checkout event' }, 400);
    const serviceKey = required(deps, 'SUPABASE_SERVICE_ROLE_KEY');
    const result = await rpc(deps, 'gateway_record_payment', { p_event_id: event.id, p_attempt_id: session.metadata.attempt_id,
      p_session_id: session.id, p_amount_sen: session.amount_total, p_currency: session.currency, p_outcome: outcome,
      p_reference: typeof session.payment_intent === 'string' ? session.payment_intent : null }, serviceKey, serviceKey);
    return json(result);
  } catch (error) {
    // Database failures must return non-2xx so Stripe retries; never acknowledge a lost payment.
    return json({ error: error instanceof HttpError && error.status === 413 ? error.message : 'Payment event could not be recorded; retry required.' }, error instanceof HttpError && error.status === 413 ? 413 : 503);
  }
}
