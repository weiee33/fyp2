import { handleDelivery } from '../_shared/delivery.ts';

// Vault holds provider credentials encrypted at rest. Only service_role can read
// this configuration; it is never returned to a caller or included in logs.
Deno.serve(async request => {
  if (request.method !== 'POST' || !/^Bearer [a-f0-9]{64}$/.test(request.headers.get('Authorization') ?? '')) {
    return new Response('Unauthorized', { status: 401 });
  }
  try {
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const response = await fetch(`${Deno.env.get('SUPABASE_URL')}/rest/v1/rpc/delivery_configuration`, {
      method: 'POST', headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: '{}', signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new Error('Configuration unavailable');
    const config = await response.json();
    return await handleDelivery(request, { env: name => config[name] ?? Deno.env.get(name), fetch, now: Date.now });
  } catch (_) { return new Response('Delivery unavailable', { status: 503 }); }
});
