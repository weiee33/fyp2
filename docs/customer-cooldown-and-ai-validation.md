# Customer cooldown display and assistant scope

## Behaviour

- Provider Details loads only the signed-in customer's cooldowns through
  `customer_service_cooldowns`. A compact MM:SS value sits beside the service
  title. The booking button is disabled until the interval ends. A monotonic
  timer measures the server-provided interval; returning to the app or booking
  screen refreshes it. The database remains authoritative on every booking.
- Registration's existing preflight keeps its backwards-compatible message and
  adds an `email_cooldown` detail containing `retry_at`. New clients display the
  exact date/time in Malaysia time, in the selected language. Both account types
  use the same preflight, and the Auth trigger still blocks direct bypasses.
- Create Account keeps the Phone Number heading and removes the redundant
  floating Mobile number label. Other screens retain their existing field label.

## Assistant scope

Chat and Assist use an independent, tool-free Gemini scope classification before
loading app data or invoking assistant tools. Unrelated requests receive a fixed
English, Chinese or Malay refusal. A second classification checks the proposed
reply before it is saved; a rejected reply exposes no action cards. Invalid scope
responses fail closed and release the turn lease. The bounded request budget
includes classification, retries and tool rounds. AI Agent's instructions also
explicitly require an app-only handoff for unrelated goals.

This is application-level scope enforcement, not model fine-tuning. Classification
is model-based and should continue to be regression-tested; it is not a guarantee
against every possible adversarial prompt. Existing ownership, tool allowlists,
customer confirmations and payment/authentication handoffs remain in effect.

Live deployed checks confirmed refusal of fruit shopping in English and Malay,
a Chinese instruction to ignore rules and provide a recipe, and a school essay
request prefixed with “In this app”. A legitimate question about booking a service
received app-specific booking and payment guidance.

## Automated checks

- PostgreSQL tests: cancellation boundaries, deletion eligibility, retained
  non-financial support cases, protected financial/other-party disputes, exact
  registration deadline details, cross-customer cooldown isolation and RLS.
- Edge tests: scope refusal, malformed classification, reply replacement,
  tool contracts, timeouts/retries, and the total generation request cap.
- Flutter tests: countdown-driven button availability, expiry/disposal, and
  Malaysia date rollover. Full Flutter suite and localization validation run
  alongside the targeted analyzer.

Phone follow-up: cancel a service, return to Provider Details, confirm the timer
counts down beside its title, background/resume the app, and retry after expiry.
Retry account deletion with only a cancelled unpaid booking and your own support
request. Check the unlock date by registering with the deleted email in either
account role. Physical-device rendering and timing require this final phone test.
