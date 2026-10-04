type Dependencies = { env: (name: string) => string | undefined; fetch: typeof fetch };
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: {...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store'} });
class RequestError extends Error { status: number; constructor(status: number, message: string) { super(message); this.status = status; } }
export async function handleDeleteAccount(request: Request, deps: Dependencies): Promise<Response> {
  if (request.method === 'OPTIONS') return new Response(null, {status: 204, headers: cors});
  if (request.method !== 'POST') return json({error: 'Use POST'},405);
  let verificationToken: string | undefined;
  const url = deps.env('SUPABASE_URL'), anon = deps.env('SUPABASE_ANON_KEY'), secret = deps.env('SUPABASE_SERVICE_ROLE_KEY');
  const call = async (path: string, method: string, key: string, token: string, body?: unknown) => {
    const r = await deps.fetch(`${url}${path}`, { method, headers: {apikey: key, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json'},
      ...(body === undefined ? {} : {body: JSON.stringify(body)}), signal: AbortSignal.timeout(20000) });
    const data = await r.json().catch(() => null);
    return {r, data};
  };
  let prepared = false;
  try {
    if (!url || !anon || !secret) throw new RequestError(503,'Account deletion is temporarily unavailable.');
    const authorization = request.headers.get('Authorization') ?? '';
    if (!/^Bearer \S+$/.test(authorization)) throw new RequestError(401,'Please sign in again.');
    const length = Number(request.headers.get('Content-Length') ?? 0);
    if (length > 4096) throw new RequestError(413,'Request too large.');
    const reader = request.body?.getReader(); let raw = ''; let bytes = 0;
    if (reader) { const decoder = new TextDecoder(); try { while (true) {
      const {done,value} = await reader.read(); if (done) break; bytes += value.byteLength;
      if (bytes > 4096) { await reader.cancel(); throw new RequestError(413,'Request too large.'); }
      raw += decoder.decode(value,{stream:true});
    } raw += decoder.decode(); } finally { reader.releaseLock(); } }
    let body: any; try { body = JSON.parse(raw); } catch { throw new RequestError(400,'Invalid request.'); }
    if (body?.confirm !== 'DELETE' || typeof body.password !== 'string' || body.password.length < 1 || body.password.length > 128)
      throw new RequestError(400,'Confirm deletion and enter your current password.');
    // getUser validates the bearer; target IDs/emails supplied by the client are never accepted.
    const {r: userResponse,data: user} = await call('/auth/v1/user','GET',anon,authorization.substring(7));
    if (!userResponse.ok || !user?.id || !user?.email) throw new RequestError(401,'Please sign in again.');
    const {r: verifyResponse,data: verified} = await call('/auth/v1/token?grant_type=password','POST',anon,anon,{email:user.email,password:body.password});
    verificationToken = verified?.access_token;
    if (!verifyResponse.ok || verified?.user?.id !== user.id || !verificationToken) throw new RequestError(403,'Your current password is incorrect or verification is unavailable. Please retry.');
    const params = {p_auth_id:user.id};
    const prep = await call('/rest/v1/rpc/customer_delete_prepare','POST',secret,secret,params);
    if (!prep.r.ok) throw new RequestError(409,prep.data?.code === 'P0001' || prep.data?.code === '42501' ? prep.data.message : 'Account deletion could not start. Please retry.');
    prepared = true;
    // Use the Storage API, never DELETE storage.objects metadata directly.
    let emptied = false;
    for (let batch = 0; batch < 10; batch++) {
      const objects = await call('/rest/v1/rpc/customer_delete_objects','POST',secret,secret,params);
      if (!objects.r.ok || !Array.isArray(objects.data)) throw new Error('object-list');
      if (objects.data.length === 0) { emptied = true; break; }
      const buckets = new Map<string,string[]>();
      for (const object of objects.data) { const names = buckets.get(object.bucket) ?? []; names.push(object.name); buckets.set(object.bucket,names); }
      for (const [bucket,prefixes] of buckets) {
        const removed = await call(`/storage/v1/object/${encodeURIComponent(bucket)}`,'DELETE',secret,secret,{prefixes});
        if (!removed.r.ok) throw new Error('object-removal');
      }
    }
    if (!emptied) throw new Error('more-storage-batches');
    const deleted = await call(`/auth/v1/admin/users/${encodeURIComponent(user.id)}`,'DELETE',secret,secret,{should_soft_delete:false});
    if (!deleted.r.ok && deleted.r.status !== 404) throw new Error('auth-removal');
    verificationToken = undefined; // Auth deletion cascades refresh sessions and identities.
    // Cleanup is complete even if recording its completion fails after Auth deletion.
    try { await call('/rest/v1/rpc/customer_delete_finish','POST',secret,secret,params); } catch { /* retry record is diagnostic only */ }
    return json({deleted:true});
  } catch (error) {
    if (error instanceof RequestError) return json({error:error.message},error.status);
    return json({error:prepared ? 'Deletion started, but cleanup has not finished. Keep this page open and retry using your current password.' : 'Account deletion could not complete. Please check your connection and retry.'},503);
  } finally {
    if (verificationToken && anon && url) {
      try { await call('/auth/v1/logout?scope=local','POST',anon,verificationToken); } catch { /* do not mask the result */ }
    }
  }
}
