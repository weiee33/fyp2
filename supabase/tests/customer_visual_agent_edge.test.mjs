import test from "node:test";
import assert from "node:assert/strict";
import {
  handleVisualAgent,
  validateAction,
  SYSTEM_INSTRUCTION,
} from "../functions/_shared/customer_visual_agent.ts";
const payload = {
  run_id: "00000000-0000-4000-8000-000000000001",
  step: 1,
  goal: "Find plumbing",
  locale: "en",
  screen: "explore",
  local_choices: false,
  image: "/9j/AAAA",
  targets: [
    { label: "Search", capability: "input", bounds: [100, 100, 900, 200] },
  ],
  history: [],
};
function fixture({
  auth = 200,
  budget = 200,
  reply = {
    action: "click",
    rationale: "Open search.",
    target_x: 500,
    target_y: 150,
  },
  upstream = 200,
} = {}) {
  const calls = [];
  return {
    calls,
    sleep: async () => {},
    env: (n) =>
      ({
        SUPABASE_URL: "https://fixture.invalid",
        SUPABASE_ANON_KEY: "anon",
        GEMINI_API_KEY: "secret-fixture",
      })[n],
    fetch: async (url, init) => {
      calls.push({ url, init });
      if (url.endsWith("/auth/v1/user"))
        return Response.json({ id: "customer" }, { status: auth });
      if (url.includes("/rpc/"))
        return Response.json(budget === 403 ? { code: "42501" } : {}, {
          status: budget,
        });
      if (upstream !== 200)
        return new Response("secret-fixture", { status: upstream });
      return Response.json({
        candidates: [
          {
            finishReason: "STOP",
            content: { parts: [{ text: JSON.stringify(reply) }] },
          },
        ],
      });
    },
  };
}
const request = (data = payload, token = true) =>
  new Request("https://fixture.invalid/agent", {
    method: "POST",
    headers: token ? { Authorization: "Bearer customer-jwt" } : {},
    body: JSON.stringify(data),
  });
test("authenticated screenshot request uses server key and brief JSON action", async () => {
  const d = fixture();
  const r = await handleVisualAgent(request(), d);
  assert.equal(r.status, 200);
  assert.equal((await r.json()).action, "click");
  assert.equal(d.calls.length, 3);
  const model = d.calls[2];
  assert.equal(model.init.headers["x-goog-api-key"], "secret-fixture");
  assert.equal(model.init.headers.Authorization, undefined);
  const b = JSON.parse(model.init.body);
  assert.equal(b.contents[0].parts[1].inlineData.mimeType, "image/jpeg");
  assert.match(SYSTEM_INSTRUCTION, /NOT private chain-of-thought/);
});
test("missing auth, denied role and quota prevent model requests", async () => {
  for (const [d, r, status] of [
    [fixture(), request(payload, false), 401],
    [fixture({ auth: 401 }), request(), 401],
    [fixture({ budget: 403 }), request(), 403],
    [fixture({ budget: 429 }), request(), 429],
  ]) {
    assert.equal((await handleVisualAgent(r, d)).status, status);
    assert.ok(d.calls.every((c) => !c.url.includes("googleapis")));
  }
});
test("rejects malformed coordinates, private thoughts and invalid text", () => {
  for (const value of [-1, 1001, NaN, Infinity, "500"])
    assert.throws(() =>
      validateAction({
        action: "click",
        rationale: "Open",
        target_x: value,
        target_y: 0,
      }),
    );
  assert.throws(() =>
    validateAction({ action: "done", rationale: "Done", thought: "hidden" }),
  );
  assert.throws(() =>
    validateAction({
      action: "input_text",
      rationale: "Type",
      target_x: 1,
      target_y: 1,
    }),
  );
  assert.throws(() =>
    validateAction({
      action: "drag_scroll",
      rationale: "Scroll",
      target_x: 1,
      target_y: 1,
    }),
  );
});
test("rejects oversized or unauthorized screen requests before quota reservation", async () => {
  for (const change of [
    { screen: "payment" },
    { local_choices: true },
    { step: 13 },
    { goal: "x".repeat(4001) },
    { image: "x".repeat(2000001) },
    { targets: [{ label: "x", capability: "execute", bounds: [0, 0, 1, 1] }] },
  ]) {
    const d = fixture();
    assert.equal(
      (await handleVisualAgent(request({ ...payload, ...change }), d)).status,
      400,
    );
    assert.equal(d.calls.length, 1);
  }
});
test("provider failures redact secrets, bounded transient retry only", async () => {
  for (const [status, count] of [
    [503, 5],
    [429, 3],
    [400, 3],
  ]) {
    const d = fixture({ upstream: status });
    const r = await handleVisualAgent(request(), d);
    assert.equal(r.status, status === 429 ? 429 : 503);
    assert.ok(!(await r.text()).includes("secret-fixture"));
    assert.equal(d.calls.length, count);
  }
});
test("invalid model output never becomes an action", async () => {
  const d = fixture({
    reply: {
      action: "click",
      rationale: "Click",
      target_x: 1001,
      target_y: 10,
    },
  });
  assert.equal((await handleVisualAgent(request(), d)).status, 502);
});

test("clarification and customer reply stay in bounded untrusted context", async () => {
  const d = fixture({reply:{action:"ask_user",rationale:"Which day works for you?"}});
  const history = [{action:"ask_user",question:"Which address?",reply:"My default home address"}];
  const r = await handleVisualAgent(request({...payload, history, blocked_bounds:[10,20,800,300]}),d);
  assert.equal(r.status,200);
  assert.equal((await r.json()).action,"ask_user");
  const context=JSON.parse(JSON.parse(d.calls[2].init.body).contents[0].parts[0].text);
  assert.deepEqual(context.history,history);
  assert.deepEqual(context.blocked_bounds,[10,20,800,300]);
  assert.match(SYSTEM_INSTRUCTION,/Never ask for passwords/);
});
test("invalid panel rectangles are rejected before reserving quota", async () => {
  for(const bounds of [[0,0,0,20],[10,20,9,50],[0,50,20,10],[0,0,1001,300],null]) {
    const d=fixture();
    assert.equal((await handleVisualAgent(request({...payload,blocked_bounds:bounds}),d)).status,400);
    assert.equal(d.calls.length,1);
  }
});


test("transient recovery backs off, switches model and reserves quota once", async () => {
  const d=fixture(); const original=d.fetch; let modelCalls=0;const delays=[];const events=[];
  d.sleep=async ms=>delays.push(ms);d.log=e=>events.push(e);
  d.fetch=async(url,init)=>{
    if(url.includes('googleapis') && modelCalls++===0){d.calls.push({url,init});return Response.json({error:{status:'UNAVAILABLE',message:'private content'}},{status:503});}
    return original(url,init);
  };
  assert.equal((await handleVisualAgent(request(),d)).status,200);
  assert.equal(delays.length,1);assert.ok(delays[0]>=1000);
  assert.match(d.calls.at(-1).url,/gemini-3.1-flash-lite/);
  assert.equal(d.calls.filter(c=>c.url.includes('/rpc/')).length,1);
  assert.equal(events[0].upstream_status,'UNAVAILABLE');
  assert.ok(!JSON.stringify(events).includes('private content'));
});
test("quota, key and model errors have distinct customer messages without retries",async()=>{
  for(const [status,pattern] of [[429,/usage limit/],[403,/key was rejected/],[404,/model is unavailable/],[400,/request configuration/]]){
    const d=fixture({upstream:status});const r=await handleVisualAgent(request(),d);
    assert.match((await r.json()).error,pattern);assert.equal(d.calls.length,3);
  }
});
test("long Retry-After does not exceed the request deadline",async()=>{
  const d=fixture();const original=d.fetch;let slept=false;
  d.sleep=async()=>{slept=true;};
  d.fetch=(url,init)=>url.includes('googleapis')?Promise.resolve(new Response('',{status:503,headers:{'retry-after':'60'}})):original(url,init);
  assert.equal((await handleVisualAgent(request(),d)).status,503);assert.equal(slept,false);
});
