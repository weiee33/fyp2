import {handleGeocode} from '../_shared/customer-geocode.ts';
Deno.serve((request: Request) => handleGeocode(request,{env:name=>Deno.env.get(name),fetch}));
