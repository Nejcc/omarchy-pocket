# Release notes

## 0.3.0

- Standard install: the plugin's service loads `pocket.lua` into Hyprland on shell start and after every config reload, so `omarchy plugin add … --enable` is the whole setup. The `dofile` line in `bindings.lua` is no longer needed; keeping it is harmless (Pocket loads once).

## 0.2.0

- Adopted workspace homes survive Hyprland config reloads.
- Optional per-monitor integration follows homes through workspace remaps.
- Offline manifest, Lua and stress-guard CI checks.

Requires the version 1 provider API only for optional per-monitor integration. Pocket still works without it. Nine offline regressions and four stress guards pass; live desktop validation is pending.
