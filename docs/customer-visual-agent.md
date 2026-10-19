# Customer visual AI Agent

AI chat preserves conversational history, photo questions, voice input and explicit action-card confirmation. AI Agent is a separate, screenshot-driven customer workflow. Start it from the customer navigation bar, choose **AI Agent**, describe a task and accept screenshot sharing.

## Architecture

`AgentHost` wraps the app Navigator. A `RepaintBoundary` captures only app content; the independent overlay contains the cursor, status/Stop panel and animated perimeter. Capture awaits a painted frame and GPU readback, then encodes an aspect-preserving JPEG (longest dimension at most 1280, quality 76) in a mobile/desktop isolate. Flutter Web's `compute` runs on its event loop. Native system surfaces, keyboards, permission sheets and other apps are outside this capture boundary.

The authenticated `customer-visual-agent` Supabase Edge Function verifies the caller with Auth and reserves a step through the customer-only quota RPC. It sends the latest JPEG as Gemini `inlineData` with `mimeType: image/jpeg`, the requested goal, locale, allowed visible target bounds and recent observed outcomes. Screenshots are not persisted in application tables or logged by this endpoint. The client saves the goal, brief progress, clarification questions, customer answers and final outcome as tagged messages in the originating AI chat. Google's processing is governed by the configured Gemini service/account terms.

The model returns exactly one JSON action. A short `rationale` explains the visible next action; private chain-of-thought is neither requested nor exposed:

```json
{"action":"click","rationale":"Open the bookings list.","target_x":500,"target_y":312}
```

Supported actions are `click`, `input_text` (replacement text), `drag_scroll` (with `end_x`, `end_y`), `done`, `handoff`, and `ask_user`. For `ask_user`, `rationale` contains one concise question; no coordinates are required. Coordinates use 0–1000 on both axes over the **entire captured image**, including the app's safe-area padding. Conversion uses the capture boundary's actual global origin and logical dimensions, not physical screen pixels. Invalid, non-finite and out-of-range coordinates are rejected on both server and client.

For each step, the client captures, predicts, compares fresh pixels and geometry, animates a 600 ms cursor, validates the screen and hit target again, then injects real Flutter pointer events. Vertical drags send pointer movements and update the cursor together. Text replacement is limited to explicitly registered controllers. The next screenshot verifies visible change. Two unchanged actions stop the run. Animated/loading content can invalidate screenshots and cause the agent to stop rather than act on stale coordinates.

## Supported customer journeys and boundaries

- Explore categories and service search; open service/provider pages.
- Open the customer's booking list and details.
- Prepare a booking by selecting a supplied address/date, available time and instructions.
- Stop at final booking submission. Payments, cancellation, messages, reviews, account changes and external pages require customer control.

Every actionable widget is registered as a click, input or handoff capability. Deepest registered hit target wins. Unregistered controls fail closed. Only dedicated local address/date pickers allow local selection without individual target registration. The model's prompt cannot override these client restrictions. The ordinary UI still applies its own authorization and validation.

The app stops on physical touch outside the agent panel, Stop, app backgrounding, account change, unsupported screen, invalid action, timeout or loop limit. A late network response cannot resume a cancelled run. A request already received by the server may still complete and consume its reserved step. The user can inspect and confirm the prepared form using the usual app controls.

## Motion and accessibility

The independent `CustomPainter` uses animation listenables, a sweep gradient and isolated repaint boundary; business pages are not rebuilt for each border frame. Thinking uses a six-second breathing cycle; execution uses a faster three-second flow. Idle fades the border out. Cursor arrival produces a visual ripple and optional selection haptic. Reduced-motion settings disable continuous animation and shorten cursor transitions. The Stop control respects top safe-area padding and is excluded from agent targets.

## Clarification panel and history

The orange panel can be dragged by its header, stays inside safe-area/keyboard bounds, and scrolls internally on small screens. Dragging it pauses action dispatch; fresh hit tests and blocked-rectangle checks prevent a subsequent tap or drag from hitting the panel. Its changing rectangle is supplied to Gemini as `blocked_bounds`. The border adds a diffuse multicolour halo and three flowing highlights on an isolated canvas.

`ask_user` enters a waiting state with a question and a 500-character answer field. Sending an answer resumes with a fresh screenshot and question/reply context. At most three clarifications are allowed within the existing 12-step/five-minute run budget. Stop cancels the pending answer; late answers cannot restart the run. Sensitive information and final transaction confirmation remain outside this workflow.

`customer_ai_agent_event` saves ordered events to the owned chat with stable UUIDs for idempotent retries. Events cannot contain executable action cards or image paths. The existing message pager retains live action-card statuses and adds origin/kind tags. Agent history is rendered as **AI Agent** activity, while the chat gateway treats all client-written agent content as untrusted user context rather than trusted model messages. A failed write remains queued in memory and exposes **Retry saving**; keep the app open until that warning clears. Screenshots are not part of saved history. Deleted chats cannot be recreated by late event retries.

## Model and deployment

The former `google_generative_ai` client SDK is deprecated. This project keeps the Gemini key in the existing authenticated server gateway instead of introducing that SDK or embedding a key in the APK. The default model is `gemini-3.6-flash`, overrideable with `GEMINI_AGENT_MODEL`; the bounded transient-failure fallback is `gemini-3.1-flash-lite`. Gemini 1.5 Pro is not hardcoded. This implementation uses the current Gemini REST `generateContent` vision/JSON API, not Google's separate Computer Use tool protocol.

References: [Google migration guidance](https://firebase.google.com/docs/ai-logic/migrate-from-google-ai-client-sdks), [Gemini models](https://ai.google.dev/gemini-api/docs/models).

Required secrets reuse `GEMINI_API_KEY`, `SUPABASE_URL`, and `SUPABASE_ANON_KEY`. JWT verification remains enabled. Apply `20261019044640_customer_visual_agent_budget.sql` before deploying `customer-visual-agent`. Apply `20261019143758_customer_agent_conversation_history.sql` and deploy the updated `customer-assistant` gateway for tagged agent history.

Quota: 12 steps/run, five-minute run expiry, one-second minimum between reservations, two starts/customer/minute, 20 starts/customer/day, 500 total starts/day. Reservations are atomic and never refunded on upstream failure. The private ledger stores only run ID, owner/auth IDs, timestamps and step count; old rows are pruned after two days when reserving a step. Account deletion cascades to ledger rows.

## Validation

- Flutter protocol, actual gesture injection, text-controller isolation, stale/rotated viewport rejection, cancellation, denied controls, scroll and overlay lifecycle tests.
- Real RepaintBoundary readback/JPEG test verifies the status overlay is excluded.
- Existing AI chat photo, voice, history, retry and explicit-confirmation regressions.
- Node endpoint tests for auth/role/quota enforcement, malformed/oversized payloads, JSON/coordinate checks, bounded fallback and secret redaction.
- Transactional SQL regression with synthetic users and rollback: owner isolation, sequence, pacing, expiry, private-table access, customer-only and anonymous boundaries.
- Live Gemini synthetic screenshot probe returned `click` at `(500,312)`, within the supplied button bounds. Diagnostic retired to HTTP 410 immediately afterward; it has no model access.

Device-specific edge clipping, keyboard behavior and end-to-end multi-step model accuracy still need acceptance testing on physical phones. This is an app-scoped assistant, not an OS accessibility service.

Additional validation covers question/reply continuation, draggable panel interaction, keyboard/large-text layout, ordered retry events, untrusted history classification, and transactional transcript ownership/deletion checks.
