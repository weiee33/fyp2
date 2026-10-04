import { handleRecovery } from '../_shared/customer-recovery.ts';
Deno.serve((request: Request) => handleRecovery(request,{env:(name)=>Deno.env.get(name),fetch}));
