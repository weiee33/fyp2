# Latest customer commit integration review

Reviewed and incorporated GitHub commit `d77f289` (customer overall) into the admin/Auth repair branch. New customer screens, notifications, profile pages, browsing routes and `timeago` dependency are preserved. The home-screen merge keeps the real customer name/navigation and the repaired empty/error states.

These remaining issues must not be resolved by giving the mobile client broad database write privileges:

| Area | Current implementation and required follow-up |
|---|---|
| Booking | `customer_transaction_service.dart` uses hardcoded time slots, trusts a client total, and inserts directly. Implement an atomic reservation RPC that derives price and provider from the service, validates the saved address and provider working hours/capacity, and handles conflicts. Current client INSERT remains denied. |
| FPX payment | `processFpxPayment` generates a random reference and attempts to store Success/escrow-held directly, then confirms the booking. This is a simulation, **not FPX sandbox integration or real escrow**. Those writes remain denied. A trusted gateway session/webhook must own payment status and reconcile duplicate events before enabling checkout. No genuine payment or escrow claim should be made from this code. |
| Search/provider details | `customer_browsing_service.dart` joins private `users` rows and requests `provider_profiles.*`, including columns not granted to customers. This is still incompatible with privacy rules. Extend the deliberately limited discovery API to support search/detail projections, filtering and pagination; do not expose phone/licence/admin-verification fields merely to make joins work. The repaired home directory itself uses a safe projection. |
| Reviews | Eligibility is checked only on the client and submission tries a direct INSERT. Implement a completed-booking, owner-checked transaction and derive the provider from that booking. `reviews_bucket` does not exist; upload needs a defined bucket, type/size restrictions and owner policies. The review eligibility embed now names the original FK to avoid ambiguity from the new composite relationship. |
| Profile | Preference updates lack a permitted write path and currently follow a separate user update, allowing partial success. Use an atomic profile update. Avatar paths use `customer_<uid>/...` but Storage policy expects `<auth-uid>/...`; adjust that convention before testing uploads. |
| Notifications | Read/mark-read permissions exist. Direct DELETE for swipe dismissal is not granted. Define deliberate dismissal/retention behavior, and wait for successful persistence before removing a UI item. |
| Identity | New services still assume application user_id equals Auth id. Use `account_identity` or ownership through RLS consistently, as in the repaired auth/home/address services. |

The newly added screens are preserved as the user's work. This repair completes the admin activation flow and the audited identity/address fixes; it does not represent these unfinished customer backend integrations as working or weaken payment/review permissions to make prototype writes succeed.
