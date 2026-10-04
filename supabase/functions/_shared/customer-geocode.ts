type Dependencies = { env: (name: string) => string | undefined; fetch: typeof fetch };
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const json = (data: unknown, status=200) => new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store',...(status===429?{'Retry-After':'2'}:{})}});
export function addressFields(data: any): Record<string,string> {
  const a = data?.properties ?? {};
  if (a.countrycode && a.countrycode.toUpperCase() !== 'MY') return {addressLine:'',city:'',state:'',postcode:''};
  const road = a.street ?? a.locality ?? a.district ?? '';
  const line = [...new Set([a.name,a.housenumber,road].filter(Boolean))].join(', ');
  const city = a.city ?? a.town ?? a.village ?? a.county ?? '';
  let state = a.state ?? '';
  if (!state && /kuala lumpur|putrajaya|labuan/i.test(city)) state = city;
  return {addressLine:String(line),city:String(city),state:String(state),postcode:String(a.postcode ?? '')};
}
export async function handleGeocode(request: Request,deps: Dependencies): Promise<Response> {
 if (request.method==='OPTIONS') return new Response(null,{status:204,headers:cors});
 if (request.method!=='POST') return json({error:'Use POST'},405);
 let stage='request';
 try {
  const url=deps.env('SUPABASE_URL'),anon=deps.env('SUPABASE_ANON_KEY'),secret=deps.env('SUPABASE_SERVICE_ROLE_KEY');
  if (!url||!anon||!secret) return json({error:'Address lookup is unavailable.'},503);
  const authorization=request.headers.get('Authorization') ?? '';
  if (!/^Bearer \S+$/.test(authorization)) return json({error:'Please sign in again.'},401);
  // Bound the body while streaming, including requests without Content-Length.
  const reader=request.body?.getReader(); let raw='',bytes=0;
  if(reader){const decoder=new TextDecoder();try{while(true){const {done,value}=await reader.read();if(done)break;bytes+=value.byteLength;
   if(bytes>2048){await reader.cancel();return json({error:'Address query is too long.'},413);}raw+=decoder.decode(value,{stream:true});}raw+=decoder.decode();}finally{reader.releaseLock();}}
  let body:any;try{body=JSON.parse(raw);}catch{return json({error:'Invalid address query.'},400);}
  const params=new URLSearchParams({lang:'en',limit:'1'});
  let key:string, path:string;
  if(body?.kind==='reverse' && typeof body.lat==='number' && typeof body.lng==='number' && Number.isFinite(body.lat) && Number.isFinite(body.lng) && Math.abs(body.lat)<=90 && Math.abs(body.lng)<=180){
    const lat=body.lat.toFixed(5),lng=body.lng.toFixed(5);key=`photon:r:${lat}:${lng}`;path='reverse';params.set('lat',lat);params.set('lon',lng);params.set('radius','1');
  } else if(body?.kind==='search' && typeof body.query==='string' && body.query.trim().length>=2 && body.query.trim().length<=150){
    const q=body.query.trim();key=`photon:s:${q.toLowerCase()}`;path='api';params.set('q',q);params.set('countrycode','MY');params.set('limit','1');
  } else return json({error:'Enter a valid Malaysian address or map location.'},400);
  const rpc=async(name:string,body:unknown,admin=true)=>{
    const response=await deps.fetch(`${url}/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:admin?secret:anon,Authorization:admin?`Bearer ${secret}`:authorization,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(10000)});
    if(!response.ok)throw new Error('rpc');const raw=await response.text();return raw?JSON.parse(raw):null;
  };
  // Active, verified customer identity is checked by the database, not user metadata.
  let identity:any;try{identity=await rpc('account_identity',{},false);}catch{return json({error:'Please sign in with an active customer account.'},403);}
  if(identity?.role!=='customer')return json({error:'A customer account is required.'},403);
  const claim=await rpc('customer_geocode_claim',{p_key:key});
  if(claim.cached!==undefined)return json(claim.cached.value);
  if(!claim.allowed)return json({error:'Address lookup is busy. Please retry in a moment.'},429);
  const base=deps.env('PHOTON_URL') ?? 'https://photon.komoot.io';
  stage='provider';
  const result=await deps.fetch(`${base.replace(/\/$/,'')}/${path}?${params}`,{headers:{'User-Agent':'LocalLifeFYP/1.0 (https://github.com/weiee33/fyp2)','Accept-Language':'en'},signal:AbortSignal.timeout(10000)});
  if(result.status===429)return json({error:'Address lookup is busy. Please retry in a moment.'},429);
  if(!result.ok)return json({error:'Address lookup is unavailable. You can enter the address manually.'},502);
  stage='decode';
  const source=await result.json();
  const first=source?.features?.[0];
  const coordinate=first?.geometry?.coordinates;
  const data=path==='reverse'?addressFields(first):first && first.properties?.countrycode?.toUpperCase()==='MY' && Array.isArray(coordinate) && coordinate.length===2 && coordinate.every(Number.isFinite)
    ? {lat:coordinate[1],lng:coordinate[0],displayName:[first.properties.name,first.properties.city,first.properties.state].filter(Boolean).join(', ')} : null;
  stage='cache';
  try { await rpc('customer_geocode_store',{p_key:key,p_result:{value:data}}); }
  catch { console.warn('customer-geocode cache write unavailable'); }
  return json(data);
 } catch (error) {
  console.warn('customer-geocode failed', stage, error instanceof Error ? error.name : 'UnknownError');
  return json({error:'Address lookup is unavailable. Please retry or enter the address manually.', code:stage},503);
 }
}
