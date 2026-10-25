import { handleRefund } from '../_shared/refunds.ts';
Deno.serve(request => handleRefund(request, {env:name=>Deno.env.get(name),fetch,now:()=>Date.now()}));
