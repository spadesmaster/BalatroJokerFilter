# Changelog

## 0.5.6
- Hardened startup against missing `SMODS.current_mod` and other init-order edge cases.
- Added lightweight Joker Filter logging for recoverable failures.
- Wrapped config save / toolbar rebuild / Cartomancer override paths in guarded calls.
- Added config-tab fallbacks when Steamodded UI helper functions are unavailable.
- Added a fallback call back into Cartomancer's original toolbar builder if Joker Filter injection fails.
- Guarded hidden-card checks in `Card:draw()` and `Card:click()` to avoid crashing on filter-state errors.

## 0.5.5
- User-local sync / commit point before hardening pass.

## 0.5.4
- Removed Show All from the config UI so the toggle grid is a clean 3 rows of 3.
- Reduced Slot pill width from the oversized test version.
- Kept config persistence working as confirmed in testing.

## 0.5.3
- Compacted the in-game Config tab so it takes less vertical space.
- Grouped show-button toggles into 3-per-row layout where possible.
- Widened the Slot pill so its text stays readable.
