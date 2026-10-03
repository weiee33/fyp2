import { handleWebhook } from '../_shared/fpx.ts';
// Stripe authenticates with a signature over the raw request; a Supabase JWT is not used.
Deno.serve((request: Request) => handleWebhook(request, { env: name => Deno.env.get(name), fetch, now: () => Date.now() }));
