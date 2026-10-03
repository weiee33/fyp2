import { handleCheckout } from '../_shared/fpx.ts';
Deno.serve((request: Request) => handleCheckout(request, { env: name => Deno.env.get(name), fetch, now: () => Date.now() }));
