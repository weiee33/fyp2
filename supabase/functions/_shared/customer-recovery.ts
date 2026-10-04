type Dependencies = { env: (name: string) => string | undefined; fetch: typeof fetch };
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'};
const json = (data: unknown,status=200) => new Response(JSON.stringify(data), {status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store',...(status===429?{'Retry-After':'3600'}:{})}});
export async function handleRecovery(request: Request,deps: Dependencies): Promise<Response> {
 if(request.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(request.method!=='POST')return json({error:'Use POST'},405);
 try {
  const url=deps.env('SUPABASE_URL'),anon=deps.env('SUPABASE_ANON_KEY'),secret=deps.env('SUPABASE_SERVICE_ROLE_KEY');
  if(!url||!anon||!secret)return json({error:'Password recovery is unavailable.'},503);
  const reader=request.body?.getReader();let raw='',size=0;
  if(reader){const decoder=new TextDecoder();try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>1024){await reader.cancel();return json({error:'Request is too large.'},413);}raw+=decoder.decode(value,{stream:true});}raw+=decoder.decode();}finally{reader.releaseLock();}}
  let body:any;try{body=JSON.parse(raw);}catch{return json({error:'Enter a valid email address.'},400);}
  const email=typeof body?.email==='string'?body.email.trim().toLowerCase():'';
  if(email.length>254||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))return json({error:'Enter a valid email address.'},400);
  const ip=request.headers.get('x-forwarded-for')?.split(',')[0].trim()||request.headers.get('x-real-ip')||'unknown';
  const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(secret+':'+ip));
  const hash=Array.from(new Uint8Array(digest)).map(x=>x.toString(16).padStart(2,'0')).join('');
  const check=await deps.fetch(url+'/rest/v1/rpc/customer_recovery_check',{method:'POST',headers:{apikey:secret,Authorization:'Bearer '+secret,'Content-Type':'application/json'},body:JSON.stringify({p_email:email,p_ip_hash:hash}),signal:AbortSignal.timeout(12000)});
  if(!check.ok)return json({error:'Could not validate the account. Please retry.'},503);
  const result=await check.json();
  if(result.allowed!==true)return json({error:'Too many recovery attempts. Please try again in one hour.'},429);
  if(result.registered!==true)return json({error:'No active, verified customer account is registered with this email. Please check your email or register first.'},404);
  // Supabase sends the configured recovery OTP. No user creation or admin password update.
  const sent=await deps.fetch(url+'/auth/v1/recover',{method:'POST',headers:{apikey:anon,'Content-Type':'application/json'},body:JSON.stringify({email}),signal:AbortSignal.timeout(15000)});
  if(!sent.ok)return json({error:sent.status===429?'Please wait before requesting another verification code.':'The verification email could not be sent. Please retry.'},sent.status===429?429:503);
  return json({sent:true});
 }catch{return json({error:'Password recovery is temporarily unavailable. Please retry.'},503);}
}
