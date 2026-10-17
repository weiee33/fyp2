# Scroll boundaries and floating customer navigation

The shared customer refresh widget previously armed a second refresh after dragging beyond the bottom. Explicit bouncing physics across customer lists/forms amplified the movement, and Android's stretch indicator could distort the viewport at the same time.

CustomerRefresh now uses a single top-edge RefreshIndicator, accepting only primary forward vertical scroll notifications. Short lists keep AlwaysScrollableScrollPhysics so they can still be refreshed. Explicit bounce physics is replaced with clamping across customer screens and shared chat; the application scroll behaviour also clamps platform defaults and removes the stretch/glow decorator for customer and provider routes. Horizontal filters, nested lists and reversed conversations cannot trigger page refresh. Conversations retain live updates, error retry and older-message loading, with a toolbar refresh action for manual reloads.

Customer navigation is positioned over a full-height body. A rounded clip limits the 14-pixel backdrop blur to the translucent white pill, with a subtle border/shadow and the raised orange AI action. The overlay sits 12 pixels above the device bottom safe area and is hidden while the keyboard is open.

An inherited inset is consumed inside the Explore, Bookings, Notifications and Profile scroll content. It includes the full navigation height, floating margin, device safe area and 12 pixels of clearance. The viewport remains behind the bar while the final items can scroll above it. Pushed routes do not inherit the root-tab inset.

Regression coverage exercises bottom and middle drags, top refresh without concurrent requests, short lists, horizontal children and reversed conversations. Layout checks use the actual four customer tabs at 320- and 393-pixel widths with a 24-pixel bottom safe area, verifying full-height viewports and reachable final content.
