# Scroll boundaries and floating customer navigation

The shared customer refresh widget previously armed a second refresh after dragging beyond the bottom. Explicit bouncing physics across customer lists/forms amplified the movement, and Android's stretch indicator could distort the viewport at the same time.

CustomerRefresh uses a single top-edge RefreshIndicator, accepting only primary forward vertical scroll notifications. Short lists keep AlwaysScrollableScrollPhysics so they can still be refreshed. The subsequent [customer support and scrolling update](customer-support-experience.md) restores a single rubber-band bounce to customer routes, while suppressing the separate Android stretch/glow decorator. Reduced motion and provider routes retain clamping. Horizontal filters, nested lists and reversed conversations cannot trigger page refresh. Customer conversations retain live updates, resume refresh, error retry and older-message loading; the toolbar refresh action is now provider-only.

Customer navigation is positioned over a full-height body. A rounded clip limits the 14-pixel backdrop blur to the translucent white pill, with a subtle border/shadow and the raised orange AI action. The overlay sits 12 pixels above the device bottom safe area and is hidden while the keyboard is open.

An inherited inset is consumed inside the Explore, Bookings, Notifications and Profile scroll content. It includes the full navigation height, floating margin, device safe area and 12 pixels of clearance. The viewport remains behind the bar while the final items can scroll above it. Pushed routes do not inherit the root-tab inset.

Regression coverage exercises bottom and middle drags, top refresh without concurrent requests, short lists, horizontal children and reversed conversations. Layout checks use the actual four customer tabs at 320- and 393-pixel widths with a 24-pixel bottom safe area, verifying full-height viewports and reachable final content.
