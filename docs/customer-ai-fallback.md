# Customer AI provider fallback

Gemini remains the primary provider. When `OPENROUTER_API_KEY` is configured in
Supabase Edge Function secrets, the assistant and visual agent use the shared
server-side router. No Flutter update or client API key is required.

## Configuration

Keep `GEMINI_API_KEY` and add `OPENROUTER_API_KEY` in Supabase → Edge Functions →
Secrets. With no model-list setting, the backend uses these tested defaults:

```text
inclusionai/ling-3.2-flash:free,baidu/ernie-5.5-flash-preview:free
```

An optional secret named `OPENROUTER_FREE_MODELS` can contain a comma-separated
list in priority order. Use exact model IDs, without JSON brackets or quotes.
Only explicit `organization/model:free` IDs are accepted, with at most five
entries. A paid ID, mixed list, empty list, or automatic router is rejected.
Removing `OPENROUTER_API_KEY` restores the previous Gemini-only implementation.

The default Ling model supports image requests. ERNIE is text-only and is skipped
for screenshots/photos. A listed model is not automatically eligible: before
using it, the router checks the live catalogue for zero pricing and the required
tools, structured-output and image capabilities. Catalogue results are cached
for five minutes. Catalogue failures prevent OpenRouter calls rather than
assuming a model is free. Prices and availability can change.

Every completion request additionally sets `provider.max_price` to zero for
prompt, completion, request and image pricing, requires parameter support, and
disallows providers that collect data. No paid model, automatic router, web
search plugin or paid fallback is configured. These controls apply to OpenRouter;
the existing direct Gemini account retains its own billing/quota configuration.

## Recovery and app boundaries

- Switching happens only around generation, never around database tool execution.
  Explicit conversation messages, tool IDs and completed results are translated
  between APIs. Gemini thought signatures are not sent to OpenRouter. A turn that
  has abandoned Gemini stays on OpenRouter so foreign tool history cannot be sent
  back to Gemini. The customer still confirms staged changes.
- The router handles quota, transport, timeout and availability failures with a
  bounded attempt/deadline budget. It remembers unhealthy models in the current
  Edge isolate and honours Retry-After cooldowns; these are not a distributed
  quota system. Other isolates may independently observe the same limit.
- OpenRouter platform quota, invalid-key and credit failures stop that account's
  chain. An explicit upstream provider rate limit can try another eligible model.
  Free-model quotas are shared: multiple models/keys do not multiply them.
- Input and proposed replies pass through the same app-only classifier using the
  fallback router. The visual agent checks its goal and proposed action as well.
  Refusals and malformed/truncated model output are terminal, not reasons to seek
  a more permissive model. If checks cannot complete, no unchecked result is sent.
- Each customer message can use several model requests. Internal reasoning also
  consumes output tokens on some OpenRouter models; structured responses reserve
  at least 1,024 tokens to avoid truncating the classification JSON.
- Logs contain model IDs, HTTP status and allowlisted transport error names only.
  Keys, prompts, raw upstream errors and reasoning are not logged.

## Validation

Run:

```sh
node --experimental-strip-types --test supabase/tests/customer_ai_edge.test.mjs supabase/tests/customer_visual_agent_edge.test.mjs supabase/tests/customer_ai_router.test.mjs
```

Tests cover free-only settings, pricing changes, capability filtering, shared vs
provider quotas, cooldowns, deadlines, stream timeouts, refusal handling, schema
checks, tool-history conversion and no repeated database execution on failover.

Live synthetic checks in Supabase forced a Gemini quota response while using the
saved OpenRouter key. Both default models accepted app-related questions, refused
an unrelated recipe/prompt-override request, and returned a valid search tool
call. Ling also read an image and returned the requested JSON. Successful calls
reported zero cost. These checks used synthetic prompts and did not change any
customer booking or account. They are sampled behaviour checks, not a guarantee
that a probabilistic model can never misclassify a future request.

After deployment, phone smoke checks: ask how to book a plumber; ask for a real
provider's services; ask an unrelated question; and identify a service from a
photo. Verify that bookings still require confirmation. Free providers may be
unavailable or slow; if all eligible providers fail, the app returns retry guidance.

References: [OpenRouter provider routing](https://openrouter.ai/docs/guides/routing/provider-selection),
[tool calling](https://openrouter.ai/docs/guides/features/tool-calling),
[limits](https://openrouter.ai/docs/api_reference/limits),
[Supabase secrets](https://supabase.com/docs/guides/functions/secrets).
