# Admin workspace review — 23 October 2026

## Interface and workflow changes

- Desktop navigation expands on pointer hover or keyboard focus. Pinning keeps it open and is remembered locally. Narrow screens retain an explicit navigation toggle.
- User, provider, category, booking, review and support details open in a modal instead of below the records table. Section shortcuts, a sticky heading, Escape handling and focus restoration make longer records easier to use.
- Closing a record or completing an action retains the current search, status and page. Unsaved edits require confirmation before dismissal.
- Validation and concurrency errors reopen the record with fresh server data and recover visible input. CSRF tokens, concurrency versions and hidden action values are never restored from submitted data. If a concurrent change removes the action, the draft remains readable without recreating the mutation form.
- Find page (Ctrl/Cmd+K), refresh, an Expired booking filter, shorter guidance and collapsible metric/activation explanations reduce navigation and reading overhead. Required warnings and customer-visible effects remain explicit.
- Reduced-motion preferences disable the added transitions. Existing roles, MFA, CSRF, audit history and database authorization remain enforced.

## Verification

- 64 isolated PHP HTTP regression tests passed on PHP 8.4.27, including filtered redirects, modal form context, escaped draft recovery, concurrent closure, CSRF, MFA, safe uploads, reports and invitation authorization.
- All 18 PHP files passed syntax checks; the browser script passed `node --check`.
- Supabase transaction A: admin foundation plus customer support — 135 assertions passed.
- Supabase transaction B: admin foundation, policy indexes, analytics, customer auth/modules, FPX and invitations — 234 assertions passed. The transactions share foundation tests; these counts are not additive.
- Both database runs used synthetic fixtures and ended with `ROLLBACK`. No real customers, invitations, emails or payments were changed.
- Browser checks used the isolated synthetic preview at desktop and narrow-screen sizes: page search, pinned/collapsed/expanded navigation, record modal focus, Escape, discard cancellation, draft retention, concurrent closure and mobile navigation.

## Boundaries

The database checks verify admin/customer contracts and authorization, not delivery by an external email provider or a live banking transaction. Refund actions continue to record requests; they do not themselves move funds. Deployment remains a separate step after review and merge. Admin invitation activation still uses the existing email verification and MFA flow, with shareable invitation links as requested.
