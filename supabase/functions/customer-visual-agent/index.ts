import {handleVisualAgent} from '../_shared/customer_visual_agent.ts';
Deno.serve((request:Request)=>handleVisualAgent(request,{env:name=>Deno.env.get(name),fetch}));
