import { handleAssistant } from '../_shared/customer_ai.ts';
Deno.serve((request: Request) => handleAssistant(request, {env: name => Deno.env.get(name), fetch, log: event => console.warn(JSON.stringify(event))}));
