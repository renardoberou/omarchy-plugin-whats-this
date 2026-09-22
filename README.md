# Help

An Omarchy shell plugin: toggle it on from the bar, then hover anything —
a bar icon, or a control inside a running app — and a card shows what it
is and (where available) what it does. Toggle off anytime, same button.

## What it does

- **Bar toggle:** click the bar icon to arm/disarm. Off by default — the
  daemon doesn't run at all until you turn it on.
- **Tiered hover resolution**, `bin/omarchy-help-daemon` polls the cursor
  ~12x/sec (`hyprctl cursorpos`) and resolves what's under it:
  1. **AT-SPI** (`tier: "atspi"`) — the Linux accessibility bus. Best
     coverage on GTK apps, which is where per-control name/role/description
     actually comes from. Requires `python-gobject`.
  2. **Window** (`tier: "window"`) — falls back to a Hyprland
     client-at-point hit test (`hyprctl clients -j`) when AT-SPI has
     nothing for that point. Always available, identifies the app/window,
     not individual controls inside it.
  3. **Nothing** — no card.
  The card shows which tier answered, so coverage gaps are visible
  per-hover instead of silently inconsistent.
- **Card** follows the cursor, click-through (same layer-shell technique as
  `omarchy-keycaps`) — it can never intercept a click meant for whatever's
  underneath it.

## Prerequisite

```bash
sudo pacman -S --needed python-gobject
```

**The daemon runs fine without this** — it degrades to window-level
identification only (tier 2) and logs why to stderr, rather than refusing
to start. Install `python-gobject` to enable tier-1 AT-SPI resolution.

## Structure

```
manifest.json          schema + three entry points (service, bar-widget, overlay)
Service.qml              headless: toggle state, owns the daemon process
BarWidget.qml             bar pill toggle
Overlay.qml                click-through card, tracks the cursor
Model.js                   pure: JSON line parsing, tier badge text
bin/omarchy-help-daemon  cursor poll -> AT-SPI hit -> Hyprland window hit -> JSON
```

## Install / remove

```
omarchy plugin add https://github.com/renardoberou/omarchy-plugin-help --enable
omarchy plugin remove renardoberou.help
```

## Local dev

```
omarchy plugin validate .
ln -sfn "$PWD" ~/.config/omarchy/plugins/renardoberou.help
omarchy plugin enable renardoberou.help
omarchy restart shell
journalctl --user -t omarchy-shell --since "1 minute ago" | grep -i help
```

Run the daemon directly to see its JSON stream without the shell at all:
```
./bin/omarchy-help-daemon
```
Confirmed live on this machine: with `python-gobject` not yet installed,
it correctly logs the degradation to stderr and still emits real
`tier: "window"` hits (e.g. hovering a game window correctly returned its
Steam app id and title).

`node -e "require('./Model.js').parseHoverLine('...')"` exercises the pure
parsing logic without the daemon, AT-SPI, or the shell at all.

## Known limits

- **AT-SPI coverage is toolkit-dependent.** Strong for GTK. Unverified for
  Qt on this machine (no Qt app was available to test against at
  authoring time). Frequently thin-to-absent for Electron apps — many ship
  their accessibility bridge off by default, or expose only coarse
  landmarks rather than per-control detail. Tier 2 is the honest ceiling
  for those apps.
- **Whether Omarchy's own bar exposes anything over AT-SPI is unverified.**
  Quickshell only publishes an accessibility tree if Qt's bridge is active
  (nothing on this machine currently forces that on). If it does turn out
  to be exposed, tier 1 will identify bar icons for free — this daemon
  doesn't special-case the bar. If it doesn't, hovering the bar currently
  falls through to tier 2, which identifies the shell's own window
  generically rather than the specific icon underneath the cursor — a
  real gap, not silently swallowed (the "window" tier badge signals it).
  Closing that gap for the bar specifically (e.g. cross-referencing cursor
  position against each widget's known layout + `omarchy plugin list
  --json` manifest descriptions) is a documented follow-up, not done here.
- **Tier 2's overlap handling is a heuristic.** `hyprctl clients -j` gives
  no real z-order/stacking data; overlapping floating windows are resolved
  by `focusHistoryID`, which can misattribute the hover to the wrong one.
- **No caching.** Every hover is a fresh round-trip; very fast mouse
  movement across many controls on a slow AT-SPI bridge could show
  visible lag.
