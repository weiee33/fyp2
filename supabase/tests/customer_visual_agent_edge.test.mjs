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
    [503, 4],
    [429, 3],
    [400, 3],
  ]) {
    const d = fixture({ upstream: status });
    const r = await handleVisualAgent(request(), d);
    assert.equal(r.status, 503);
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
