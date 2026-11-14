// Provider routing is server-owned. Clients cannot choose models or pricing.
export const DEFAULT_FREE_MODELS = [
  'inclusionai/ling-3.2-flash:free',
  'baidu/ernie-5.5-flash-preview:free',
];
type Dependencies = {
  env: (name: string) => string | undefined;
  fetch: typeof fetch;
  now?: () => number;
  log?: (event: Record<string, unknown>) => void;
};
export class ModelFailure extends Error {
  status: number;
  constructor(status = 503) {
    super('The AI is temporarily busy. Please retry shortly.');
    this.status = status;
  }
}
const states = new WeakMap<typeof fetch, {
  catalogue?: { until: number; models: any[] };
  cooldown: Map<string, number>;
}>();

export function freeModelList(value?: string): string[] {
  const models = value === undefined ? DEFAULT_FREE_MODELS : value.split(',').map(x => x.trim());
  if (!models.length || models.length > 5 || models.some(x =>
    !/^[a-z0-9-]+\/[a-z0-9._-]+:free$/.test(x))) {
    throw new ModelFailure();
  }
  return [...new Set(models)];
}

async function read(response: Response, limit = 200000): Promise<any> {
  const reader = response.body?.getReader();
  if (!reader) throw new ModelFailure();
  const chunks: Uint8Array[] = []; let size = 0;
  try {
    for (;;) {
      const {done, value} = await reader.read();
      if (done) break;
      size += value.length;
      if (size > limit) { await reader.cancel(); throw new ModelFailure(); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  try { return JSON.parse(new TextDecoder().decode(bytes)); }
  catch { throw new ModelFailure(); }
}

function jsonSchema(value: any): any {
  if (Array.isArray(value)) return value.map(jsonSchema);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(Object.entries(value).filter(([k]) => k !== 'propertyOrdering')
    .map(([k, v]) => [k, k === 'type' && typeof v === 'string' ? v.toLowerCase() : jsonSchema(v)]));
}

/** Translate only explicit messages/tool results; never replay tool execution. */
export function openRouterBody(body: any, model: string): any {
  const messages: any[] = [{role: 'system', content: (body.systemInstruction?.parts ?? [])
    .filter((p: any) => typeof p.text === 'string').map((p: any) => p.text).join('\n')}];
  const pending: {id: string; name: string}[] = [];
  let serial = 0;
  for (const turn of body.contents ?? []) {
    const content: any[] = [], calls: any[] = [], results: any[] = [];
    for (const p of turn.parts ?? []) {
      if (p.thought) continue;
      if (typeof p.text === 'string') content.push({type: 'text', text: p.text});
      if (p.inlineData) content.push({type: 'image_url', image_url: {
        url: `data:${p.inlineData.mimeType};base64,${p.inlineData.data}`,
      }});
      if (p.functionCall) {
        const f = p.functionCall;
        const id = f.id || `call_${serial++}`;
        pending.push({id, name: f.name});
        calls.push({id, type: 'function', function: {name: f.name, arguments: JSON.stringify(f.args ?? {})}});
      }
      if (p.functionResponse) {
        const f = p.functionResponse;
        const index = pending.findIndex(x => f.id ? x.id === f.id : x.name === f.name);
        if (index < 0) throw new ModelFailure();
        const [call] = pending.splice(index, 1);
        results.push({role: 'tool', tool_call_id: call.id, content: JSON.stringify(f.response)});
      }
    }
    if (content.length || calls.length) messages.push({
      role: turn.role === 'model' ? 'assistant' : 'user',
      content: content.length ? content : null,
      ...(calls.length ? {tool_calls: calls} : {}),
      ...(turn.__openrouterModel === model && turn.__openrouterReasoning
        ? {reasoning_details: turn.__openrouterReasoning} : {}),
    });
    messages.push(...results);
  }
  const config = body.generationConfig ?? {};
  const declarations = body.tools?.flatMap((x: any) => x.functionDeclarations ?? []) ?? [];
  return {
    // OpenRouter reasoning models count internal reasoning against max_tokens.
    // Leave room for a complete schema response; incomplete JSON fails closed.
    model, messages, stream: false, max_tokens: Math.max(1024, config.maxOutputTokens ?? 2048),
    provider: {require_parameters: true, data_collection: 'deny',
      max_price: {prompt: 0, completion: 0, request: 0, image: 0}},
    ...(config.temperature !== undefined ? {temperature: config.temperature} : {}),
    ...(config.responseSchema ? {response_format: {type: 'json_schema', json_schema: {
      name: 'app_response', strict: true, schema: jsonSchema(config.responseSchema),
    }}} : {}),
    ...(declarations.length ? {
      tools: declarations.map((d: any) => ({type: 'function', function: {
        name: d.name, description: d.description, parameters: jsonSchema(d.parameters),
      }})),
      tool_choice: body.toolConfig?.functionCallingConfig?.mode === 'NONE' ? 'none' : 'auto',
    } : {}),
  };
}

function normalized(data: any, model: string): any {
  const choice = data?.choices?.[0], message = choice?.message;
  // A refusal is terminal. Never shop for a model that bypasses a refusal.
  if (message?.refusal || choice?.finish_reason === 'content_filter') throw new ModelFailure();
  if (!message || !['stop', 'tool_calls'].includes(choice.finish_reason)) throw new ModelFailure();
  const parts: any[] = [];
  if (typeof message.content === 'string' && message.content.trim()) parts.push({text: message.content});
  const ids = new Set<string>();
  for (const call of message.tool_calls ?? []) {
    if (call.type !== 'function' || typeof call.id !== 'string' || !call.id || ids.has(call.id) ||
      typeof call.function?.name !== 'string') throw new ModelFailure();
    ids.add(call.id);
    let args: any;
    try { args = JSON.parse(call.function.arguments); } catch { throw new ModelFailure(); }
    if (!args || typeof args !== 'object' || Array.isArray(args)) throw new ModelFailure();
    parts.push({functionCall: {id: call.id, name: call.function.name, args}});
  }
  if (!parts.length) throw new ModelFailure();
  return {candidates: [{finishReason: 'STOP', content: {role: 'model', parts,
    __openrouterModel: model, __openrouterReasoning: message.reasoning_details}}]};
}

function compatible(model: any, body: any): boolean {
  const price = model?.pricing;
  if (!price || price.prompt === undefined || price.completion === undefined ||
    Object.values(price).some(v => v == null || String(v).trim() === '' || Number(v) !== 0)) return false;
  const params = model.supported_parameters ?? [];
  if (body.tools?.length && (!params.includes('tools') || !params.includes('tool_choice'))) return false;
  if (body.generationConfig?.responseSchema && !params.includes('structured_outputs')) return false;
  if (body.contents?.some((c: any) => c.parts?.some((p: any) => p.inlineData)) &&
    !model.architecture?.input_modalities?.includes('image')) return false;
  return true;
}

/** One router per turn, shared isolate cooldowns. No database writes happen here. */
export function createModelRouter(deps: Dependencies, primary: string, deadline: number) {
  const models = freeModelList(deps.env('OPENROUTER_FREE_MODELS'));
  const key = deps.env('OPENROUTER_API_KEY'), geminiKey = deps.env('GEMINI_API_KEY');
  if (!key || !/^gemini-[a-z0-9.-]+$/.test(primary)) throw new ModelFailure();
  const now = deps.now ?? Date.now;
  let state = states.get(deps.fetch);
  if (!state) { state = {cooldown: new Map()}; states.set(deps.fetch, state); }
  const shared = state;
  let selected = geminiKey ? primary : models[0], requests = 0, geminiAbandoned = !geminiKey;
  const available = (name: string) => (shared.cooldown.get(name) ?? 0) <= now();
  const cool = (name: string, delay: number) => shared.cooldown.set(name, now() + Math.max(30000, delay));
  return async (body: Record<string, unknown>, _round: number): Promise<any> => {
    const order = [...new Set([selected, ...models])].filter(x => x !== primary || !geminiAbandoned);
    for (const model of order) {
      if (!available(model)) continue;
      const router = model.includes('/');
      if (router && !available('openrouter')) continue;
      if (deadline - now() < 1500 || requests >= 12) throw new ModelFailure();
      if (router) {
        if (!shared.catalogue || shared.catalogue.until <= now()) {
          try {
            const r = await deps.fetch('https://openrouter.ai/api/v1/models', {
              signal: AbortSignal.timeout(Math.min(5000, Math.max(1, deadline - now()))),
            });
            if (!r.ok) throw new ModelFailure();
            const data = await read(r, 5000000);
            if (!Array.isArray(data.data)) throw new ModelFailure();
            shared.catalogue = {until: now() + 300000, models: data.data};
          } catch { cool('openrouter', 30000); continue; }
        }
        if (!compatible(shared.catalogue.models.find(x => x.id === model), body)) continue;
      }
      requests++;
      let r: Response, data: any;
      try {
        r = await deps.fetch(router ? 'https://openrouter.ai/api/v1/chat/completions'
          : `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
          method: 'POST',
          headers: router ? {'Content-Type': 'application/json', Authorization: `Bearer ${key}`,
            'X-OpenRouter-Title': 'Local Life Service Assistant'}
            : {'Content-Type': 'application/json', 'x-goog-api-key': geminiKey!},
          body: JSON.stringify(router ? openRouterBody(body, model) : {...body,
            generationConfig: {maxOutputTokens: 2048, ...(body.generationConfig as any ?? {}),
              thinkingConfig: {thinkingLevel: 'MINIMAL'}}}),
          signal: AbortSignal.timeout(Math.min(16000, Math.max(1, deadline - now()))),
        });
        // fetch resolves when headers arrive; the body can still time out.
        if (r.ok) data = await read(r);
      } catch (e) {
        if (!(e instanceof Error) || !['TimeoutError', 'AbortError', 'TypeError'].includes(e.name)) throw e;
        cool(model, 30000);
        if (!router) geminiAbandoned = true;
        deps.log?.({event: 'ai_model_transport', model, reason: e.name});
        continue;
      }
      if (r.ok) {
        if (data.error) throw new ModelFailure();
        const result = router ? normalized(data, model) : data;
        selected = model;
        deps.log?.({event: 'ai_model_selected', model});
        return result;
      }
      let error: any = {};
      try { error = (await read(r, 12000))?.error ?? {}; } catch { /* Redacted. */ }
      deps.log?.({event: 'ai_model_unavailable', model, http_status: r.status});
      // Invalid input and moderation must not be bypassed by another provider.
      if (![401, 402, 404, 408, 429, 500, 502, 503, 504].includes(r.status)) throw new ModelFailure();
      const header = r.headers.get('retry-after');
      const delay = header ? (/^\d+(\.\d+)?$/.test(header) ? Number(header) * 1000 : Date.parse(header) - now()) : 30000;
      const boundedDelay = Number.isFinite(delay) ? Math.max(30000, delay) : 30000;
      cool(model, boundedDelay);
      if (!router) geminiAbandoned = true;
      // A platform quota/key/balance error affects every OpenRouter model. Only
      // explicit provider rate limits permit trying another model on that account.
      if (router && ([401, 402].includes(r.status) ||
        r.status === 429 && !error?.metadata?.provider_code)) cool('openrouter', boundedDelay);
    }
    throw new ModelFailure();
  };
}
