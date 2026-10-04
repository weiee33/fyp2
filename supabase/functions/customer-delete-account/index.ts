import { handleDeleteAccount } from '../_shared/customer-account.ts';
Deno.serve((request: Request) => handleDeleteAccount(request, {env: name => Deno.env.get(name), fetch}));
