type Dependencies = { env: (name: string) => string | undefined; fetch: typeof fetch; now: () => number };
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const response = (body: unknown, status = 200) => new Response(JSON.stringify(body), {status, headers: {'Content-Type':'application/json','Cache-Control':'no-store'}});
function setting(d: Dependencies, name: string): string {
  const value = d.env(name); if (!value) throw new Error('Refund service configuration is missing'); return value;
}
async function rpc(d: Dependencies, name: string, body: unknown, token?: string): Promise<any> {
  const key = setting(d, token ? 'SUPABASE_ANON_KEY' : 'SUPABASE_SERVICE_ROLE_KEY');
  const res = await d.fetch(`${setting(d,'SUPABASE_URL')}/rest/v1/rpc/${name}`, {method:'POST', headers:{apikey:key,Authorization:`Bearer ${token ?? key}`,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
  if (!res.ok) throw new Error('Refund authorization or state validation failed');
  return res.json();
}
async function stripe(d: Dependencies, path: string, body?: URLSearchParams, id?: string): Promise<any> {
  const key = setting(d,'STRIPE_SECRET_KEY');
  if (!key.startsWith('sk_test_')) throw new Error('Only sandbox refunds are enabled');
  const res = await d.fetch(`https://api.stripe.com/v1/${path}`, {method:body?'POST':'GET',headers:{Authorization:`Bearer ${key}`,'Stripe-Version':'2025-02-24.acacia',...(body?{'Content-Type':'application/x-www-form-urlencoded','Idempotency-Key':`local-life-refund-${id}`}:{})},body,signal:AbortSignal.timeout(15000)});
  if (!res.ok) {
    // A definitive create rejection means no refund was created. A timeout,
    // rate limit, concurrency conflict or server error remains uncertain.
    if(body && res.status>=400 && res.status<500 && ![409,429].includes(res.status)) {
      await rpc(d,'gateway_reject_refund',{p_refund_id:id});
    }
    throw new Error('Stripe refund operation did not complete');
  }
  return res.json();
}
async function record(d: Dependencies, refund: any, id: string): Promise<any> {
  if (refund?.livemode !== false || !/^re_[a-zA-Z0-9]+$/.test(refund.id ?? '') || refund.metadata?.refund_id !== id || !uuid.test(id) || !Number.isSafeInteger(refund.amount) || refund.amount<=0 || refund.currency!=='myr' || !['pending','requires_action','succeeded','failed','canceled'].includes(refund.status)) throw new Error('Invalid Stripe refund');
  return rpc(d,'gateway_record_refund',{p_refund_id:id,p_reference:refund.id,p_payment_intent:refund.payment_intent,p_amount_sen:refund.amount,p_currency:refund.currency,p_status:refund.status});
}
// Called only AFTER HMAC verification by the shared payment webhook. Retrieve
// current gateway state so delayed or duplicate events cannot reverse progress.
export async function reconcileRefundEvent(d: Dependencies, object: any): Promise<any> {
  if (!object?.metadata?.refund_id) return {ignored:true};
  if (!/^re_[a-zA-Z0-9]+$/.test(object.id ?? '') || !uuid.test(object.metadata.refund_id)) throw new Error('Invalid refund event');
  return record(d,await stripe(d,`refunds/${object.id}`),object.metadata.refund_id);
}
export async function handleRefund(request: Request, d: Dependencies): Promise<Response> {
  if (request.method!=='POST') return response({error:'Use POST'},405);
  const token = /^Bearer (\S+)$/.exec(request.headers.get('Authorization') ?? '')?.[1];
  if (!token) return response({error:'Sign in required'},401);
  let input: any;
  try {
    // Stream bound also applies when Content-Length is absent or false.
    const reader=request.body?.getReader(); let bytes=0; const chunks:Uint8Array[]=[];
    if(reader) { try { while(true) { const {done,value}=await reader.read(); if(done)break; bytes+=value.length; if(bytes>1024){await reader.cancel();throw new Error('Too large');} chunks.push(value); } } finally {reader.releaseLock();} }
    const buffer=new Uint8Array(bytes); let offset=0; for(const chunk of chunks){buffer.set(chunk,offset);offset+=chunk.length;}
    input=JSON.parse(new TextDecoder().decode(buffer));
    if (!uuid.test(input?.refund_id ?? '') || Object.keys(input).some(k=>k!=='refund_id')) throw new Error('Invalid input');
  } catch { return response({error:'Choose a valid refund request'},400); }
  try {
    // Database validates the authenticated active Super Admin and AAL2 before
    // returning trusted payment/amount, and durably reserves this request.
    const quote=await rpc(d,'admin_prepare_refund',{p_refund_id:input.refund_id},token);
    if(!/^pi_[a-zA-Z0-9]+$/.test(quote.payment_intent ?? '') || !Number.isSafeInteger(Number(quote.amount_sen)) || Number(quote.amount_sen)<=0) throw new Error('Invalid payment');
    let refund;
    if(quote.gateway_reference) {
      if(!/^re_[a-zA-Z0-9]+$/.test(quote.gateway_reference))throw new Error('Invalid reference');
      refund=await stripe(d,`refunds/${quote.gateway_reference}`);
    } else {
      // Recover a successful Stripe call whose database write/HTTP response was
      // lost. Never use a fresh idempotency key for the same request.
      let cursor=''; let found=false;
      for(let page=0;page<100;page++) {
        const list=await stripe(d,`refunds?payment_intent=${encodeURIComponent(quote.payment_intent)}&limit=100${cursor?`&starting_after=${encodeURIComponent(cursor)}`:''}`);
        if(!Array.isArray(list.data))throw new Error('Invalid refund list');
        refund=list.data.find((r:any)=>r.metadata?.refund_id===input.refund_id);
        if(refund){found=true;break;}
        if(!list.has_more)break;
        cursor=list.data.at(-1)?.id;
        if(!cursor || page===99)throw new Error('Refund reconciliation requires review');
      }
      if(!found) {
        const age=d.now()-Date.parse(quote.submitted_at);
        // Stripe may discard idempotency keys after 24 hours. An uncertain old
        // submission is deliberately left reserved for operator reconciliation.
        if(!Number.isFinite(age)||age<0||age>=23*60*60*1000)throw new Error('Old refund submission requires review');
        refund=await stripe(d,'refunds',new URLSearchParams({payment_intent:quote.payment_intent,amount:String(quote.amount_sen),'metadata[refund_id]':input.refund_id}),input.refund_id);
      }
    }
    const result=await record(d,refund,input.refund_id);
    return response({...result,message:result.status==='Succeeded'?'Stripe confirmed the refund. The customer can see it in Help Centre.':result.status==='Processing'?'Refund is processing. Refresh its status to check for confirmation.':'Refund did not complete. Review its status before trying again.'});
  } catch {
    // Timeouts/ambiguous errors NEVER mark money as returned or release the
    // reserved amount. Retrying reconciles the same request.
    return response({code:'P0001',message:'Refund could not be confirmed. Open this refund and refresh its status. Do not create another request. If it remains unresolved, reconcile its reference in Stripe.'},409);
  }
}
