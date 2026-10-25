type Dependencies = { env: (name: string) => string | undefined; fetch: typeof fetch; now: () => number };
type Job = { id: string; lease_id: string; notification_id: string; token: string; expires_at: string; payload: Record<string, any> };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
const encoder = new TextEncoder();
const base64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
function required(deps: Dependencies, key: string): string {
  const value = deps.env(key); if (!value) throw new Error('Delivery setup required'); return value;
}
async function rpc(deps: Dependencies, name: string, body: unknown) {
  const key = required(deps, 'SUPABASE_SERVICE_ROLE_KEY');
  const result = await deps.fetch(`${required(deps, 'SUPABASE_URL')}/rest/v1/rpc/${name}`, {
    method: 'POST', headers: { Authorization: `Bearer ${key}`, apikey: key, 'Content-Type': 'application/json' },
    body: JSON.stringify(body), signal: AbortSignal.timeout(15000),
  });
  if (!result.ok) throw new Error('Delivery database unavailable');
  const text = await result.text(); return text ? JSON.parse(text) : null;
}

// Only the messaging scope is requested; the service account never ships in the app.
export async function fcmAccess(deps: Dependencies): Promise<{ project: string; token: string }> {
  const account = JSON.parse(required(deps, 'FIREBASE_SERVICE_ACCOUNT'));
  if (!/^[a-z][a-z0-9-]{4,61}[a-z0-9]$/.test(account.project_id ?? '') ||
      !/^[^\s@]+@[^\s@]+\.gserviceaccount\.com$/.test(account.client_email ?? '')) throw new Error('Invalid Firebase service account');
  const now = Math.floor(deps.now() / 1000);
  const header = base64url(encoder.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const payload = base64url(encoder.encode(JSON.stringify({ iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging', aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600 })));
  const pem = account.private_key.replace(/-----[A-Z ]+-----|\s/g, '');
  const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(pem), c => c.charCodeAt(0)),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const signature = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, encoder.encode(`${header}.${payload}`)));
  const result = await deps.fetch('https://oauth2.googleapis.com/token', { method: 'POST',
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${header}.${payload}.${base64url(signature)}` }),
    signal: AbortSignal.timeout(15000) });
  if (!result.ok) throw new Error('Firebase authentication failed');
  const body = await result.json();
  if (!body.access_token) throw new Error('Firebase authentication failed');
  return { project: account.project_id, token: body.access_token };
}

export function pushCopy(title: string, language: string): { title: string; body: string } {
  const accepted = title === 'Your slot was accepted';
  const zh = language === 'zh', ms = language === 'ms';
  if (title === 'Booking requested') return {
    title: zh ? '预约已提交' : ms ? 'Tempahan Dihantar' : 'Booking Requested',
    body: zh ? '我们会在服务商回复后通知您。' : ms ? 'Kami akan memaklumkan anda apabila penyedia membalas.' : 'We’ll notify you when the provider responds.',
  };
  if (title === 'Payment verified' || title === 'FPX payment verified') return {
    title: zh ? '付款成功' : ms ? 'Pembayaran Berjaya' : 'Payment Successful',
    body: zh ? '请打开 Local Life Service Assistant 查看收据和预约。' : ms ? 'Buka Local Life Service Assistant untuk resit dan tempahan anda.' : 'Open Local Life Service Assistant to view your receipt and booking.',
  };
  // Lock-screen text deliberately omits names, addresses and payment amounts.
  return {
    title: accepted ? (zh ? '预约已接受' : ms ? 'Tempahan Diterima' : 'Booking Accepted')
      : (zh ? '预约有新消息' : ms ? 'Kemas Kini Tempahan' : 'Booking Update'),
    body: accepted ? (zh ? '请打开 Local Life Service Assistant 并在付款时限前完成付款。' : ms ? 'Buka Local Life Service Assistant dan bayar sebelum tempoh pembayaran tamat.' : 'Open Local Life Service Assistant and pay before your payment window closes.')
      : (zh ? '请打开 Local Life Service Assistant 查看重要的预约或付款更新。' : ms ? 'Buka Local Life Service Assistant untuk kemas kini penting tempahan atau pembayaran.' : 'Open Local Life Service Assistant for an important booking or payment update.'),
  };
}

export async function sendPush(job: Job, access: { project: string; token: string }, deps: Dependencies): Promise<string> {
  const remaining = Math.floor((Date.parse(job.expires_at) - deps.now()) / 1000);
  if (!Number.isFinite(remaining) || remaining <= 0) return 'rejected';
  const result = await deps.fetch(`https://fcm.googleapis.com/v1/projects/${access.project}/messages:send`, {
    method: 'POST', headers: { Authorization: `Bearer ${access.token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ message: { token: job.token,
      notification: pushCopy(job.payload.title, job.payload.language),
      data: { notification_id: job.notification_id },
      android: { priority: 'HIGH', ttl: `${Math.min(remaining, 21600)}s`,
        collapse_key: job.notification_id,
        notification: { channel_id: 'booking_alerts', icon: 'ic_stat_home_serve', color: '#FF6B00',
          tag: job.notification_id, visibility: 'PRIVATE', sound: 'default' } },
    } }), signal: AbortSignal.timeout(15000),
  });
  if (result.ok) return 'sent';
  const body = await result.json().catch(() => ({}));
  if (body.error?.details?.some((detail: any) => detail.errorCode === 'UNREGISTERED')) return 'invalid_token';
  // Credentials, quotas and temporary provider failures can be repaired and retried.
  return [400, 404].includes(result.status) ? 'rejected' : 'retry';
}

export function receiptMessage(payload: Record<string, any>) {
  const url = new URL(payload.receipt_url);
  if (url.protocol !== 'https:' || url.hostname !== 'pay.stripe.com' || url.username || url.password || url.port || !url.pathname.startsWith('/receipts/')) throw new Error('Invalid receipt URL');
  if (!Number.isSafeInteger(payload.amount_sen) || payload.amount_sen <= 0 || payload.test_mode !== true) throw new Error('Invalid receipt');
  const amount = `RM ${(payload.amount_sen / 100).toFixed(2)}`;
  const escaped = url.toString().replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
  return { subject: 'Local Life Service Assistant — Payment Receipt (Sandbox)',
    text: `Local Life Service Assistant\nPayment Receipt\n${amount}\nYour sandbox payment was verified. No real money was collected.\nView your e-receipt: ${url}\nOpen Local Life Service Assistant for your booking status.`,
    html: `<div style="background:#f7f8fa;padding:32px 16px;font-family:Arial,sans-serif;color:#172033"><div style="max-width:480px;margin:auto;background:white;border:1px solid #e5e7eb;border-radius:20px;padding:28px"><p style="color:#ff6b00;font-weight:bold;letter-spacing:1px">Local Life Service Assistant</p><h1 style="font-size:24px">Payment Receipt</h1><p style="font-size:32px;font-weight:bold">${amount}</p><p>Your sandbox payment was verified. No real money was collected.</p><a href="${escaped}" style="display:inline-block;background:#ff6b00;color:#fff;text-decoration:none;padding:14px 24px;border-radius:28px;font-weight:bold">View E-Receipt</a><p style="font-size:13px;color:#64748b;margin-top:24px">Open Local Life Service Assistant for your booking status.</p></div></div>` };
}

export async function sendReceipt(job: Job, deps: Dependencies): Promise<string> {
  // Resend's shared testing sender can deliver only to its verified account owner.
  // Never redirect a different customer's receipt to that mailbox.
  const testRecipient = deps.env('RECEIPT_TEST_RECIPIENT')?.trim().toLowerCase();
  const configuredFrom = required(deps, 'RECEIPT_FROM_EMAIL').trim();
  // Keep the verified sending mailbox; the product display name is app-owned.
  const mailbox = configuredFrom.match(/<([^<>]+)>$/)?.[1] ?? configuredFrom;
  if (!/^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$/.test(mailbox)) throw new Error('Invalid receipt sender');
  const from = `Local Life Service Assistant <${mailbox}>`;
  if (/@resend\.dev\b/i.test(from) && !testRecipient) throw new Error('Test recipient required');
  if (testRecipient && job.payload.email?.trim().toLowerCase() !== testRecipient) return 'rejected';
  const message = receiptMessage(job.payload);
  const response = await deps.fetch('https://api.resend.com/emails', { method: 'POST',
    headers: { Authorization: `Bearer ${required(deps, 'RESEND_API_KEY')}`, 'Content-Type': 'application/json', 'Idempotency-Key': `home-serve-receipt-${job.id}` },
    body: JSON.stringify({ from, to: [job.payload.email], ...message }),
    signal: AbortSignal.timeout(15000) });
  return response.ok ? 'sent' : [400, 422].includes(response.status) ? 'rejected' : 'retry';
}

export async function handleDelivery(request: Request, deps: Dependencies): Promise<Response> {
  if (request.method !== 'POST') return json({ error: 'Use POST' }, 405);
  const secret = deps.env('DELIVERY_WORKER_SECRET');
  const provided = request.headers.get('Authorization')?.replace(/^Bearer /, '') ?? '';
  if (!secret || secret.length < 32 || provided.length !== secret.length) return json({ error: 'Unauthorized' }, 401);
  let diff = 0; for (let i = 0; i < secret.length; i++) diff |= secret.charCodeAt(i) ^ provided.charCodeAt(i);
  if (diff !== 0) return json({ error: 'Unauthorized' }, 401);
  const started = deps.now();
  const counts = { sent: 0, deferred: 0 };
  const failures: string[] = [];
  for (const kind of ['push', 'email']) {
    if (deps.env(kind === 'push' ? 'DELIVERY_PUSH_ENABLED' : 'DELIVERY_EMAIL_ENABLED') !== 'true') continue;
    try {
      // Validate provider configuration before leasing jobs so outages don't consume retries.
      const access = kind === 'push' ? await fcmAccess(deps) : null;
      if (kind === 'email') { required(deps, 'RESEND_API_KEY'); required(deps, 'RECEIPT_FROM_EMAIL'); }
      const jobs: Job[] = await rpc(deps, 'claim_deliveries', { p_kind: kind });
      for (const job of jobs) {
        if (deps.now() - started > 90000) break; // Unprocessed leases become eligible again.
        let result: string;
        try { result = kind === 'push' ? await sendPush(job, access!, deps) : await sendReceipt(job, deps); }
        catch (_) { result = 'retry'; }
        await rpc(deps, 'finish_delivery', { p_id: job.id, p_lease: job.lease_id, p_result: result });
        if (result === 'sent') counts.sent++; else counts.deferred++;
      }
    } catch (_) { failures.push(kind); }
  }
  // Never log tokens, email addresses, private keys, provider response bodies or receipts.
  return json({ ...counts, unavailable: failures }, failures.length ? 503 : 200);
}
