import { handleReturn } from '../_shared/fpx.ts';
// The short-lived HMAC return link authenticates this read-only page.
// A browser redirect never marks a booking or payment successful.
Deno.serve((request: Request) => handleReturn(request, { env: name => Deno.env.get(name), fetch, now: () => Date.now() }));
