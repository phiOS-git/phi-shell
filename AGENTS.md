# phi-shell — the desktop shell

QML on Quickshell 0.3.1. One shell process for the whole session — status
bars, popouts, launcher, lock screen, settings, notifications, app switcher,
screenshot, magnifier, OSD — not a set of independent components.

**You cannot run this.** There is no compositor in an agent session, so every
visual result is verified by the user with a screenshot. Say exactly what to
look at and what should have changed.

The workspace `AGENTS.md` one level up carries the rules for every repository
and is not repeated here.

## Running it

Clone to exactly `~/.config/quickshell/phi` — Quickshell keys config by folder
name. Hyprland starts `qs -p ~/.config/quickshell/phi` on login. Quickshell
hot-reloads every loaded file on save, so editing a `.qml` file needs no
restart; a fresh process is only needed for a broken state or to watch stdout:
`pkill -x qs; qs -p ~/.config/quickshell/phi`.

## How this repo is built

`shell.qml` is the root: it mounts every surface, one per screen where that
makes sense, and owns the `image`, `workspace`, `magnifier` and `spotlight`
IPC handlers.

- **`Config/Tokens.qml` and `Config/Colors.json` are generated** by `phi theme`
  and gitignored — never edit them, never commit a copy.
  `Config/Tokens.example.qml` is the checked-in worked example. Colour lives
  in the JSON, watched live by `Config/Colors.qml`, so a variant switch
  updates colour in place instead of resetting the running session; the
  structural tokens in `Tokens.qml` do not change between variants.
- **The service surface is fenced off.** `Config/Appearance.qml`,
  `Config/Capabilities.qml` and the files under `Services/` are the only
  places that touch `Quickshell.Services.*`, `.Hyprland`, `.Wayland`,
  `.Bluetooth` or `.Networking` — the API Quickshell does not keep stable at
  0.3.x. Everything else reads one of those. Each `Services/*.qml` is a thin
  re-export of what its consumers need, no logic. `Singleton` and
  `Quickshell.Io` (`Process`, `FileView`) are foundational and used wherever a
  file legitimately bridges to an external process. Two narrow, flagged
  exceptions: `Components/Lock/Lock.qml` imports `Quickshell.Wayland` for
  `WlSessionLock`, and `Components/Bar/Bar.qml` does the same for
  `IdleInhibitor`, both because the protocol object needs a real mapped
  window.
- **Type is code, instance is data.** A bar module or a settings section is
  written once as a component; the instance is a row in
  `Components/Bar/modules-top.json`, `modules-bottom.json` or
  `Components/Settings/sections.json`. Adding one must be a one-file data
  change — if it is not, the design is wrong. `Bar.qml`'s `componentFor()` is
  the only place a new module *type* needs code.
- **`Components/qmldir`** maps each surface `shell.qml` composes to its file,
  so they resolve as `Components.Bar`, `Components.Lock`, … whether the `.qml`
  sits directly there or one level down.
- **Capability-gated.** A module declares a capability requirement and appears
  only where `Config/Capabilities.qml` reports it.
- **N monitors from day one.** One monitor today is not a reason to hardcode
  one.

## The surfaces

Two bars, top and bottom, each a three-island layout with asymmetric corner
radii. Top: the Φ agent icon and workspaces, a centre clock, then media,
screenshot, clipboard, notifications and a status popout. Bottom: a runner
trigger and the current app, a centre window list, then brightness, volume,
network, bluetooth, battery and a stats popout.

`Components/BarPopout/` is the shared popout surface — one card per bar icon,
one file per card under `modules/`, all on `Widgets/PopoutSurface.qml`, which
owns the window chrome (fade, click-outside dismiss, anchored card, radii).
Notifications and clipboard are popout cards, not their own windows.

The rest: a launcher that is a **renderer only** — ranking, providers and
actions live in `phi query`, and its modes are data; a lock screen on
`ext-session-lock` with native PAM and a selectable ambient backdrop; an app
switcher unified with Alt+Tab; home-built screenshot, OCR and QR with
`wf-recorder` for video; a native floating image window; the AI agent panel;
the settings panel; toasts; OSD; magnifier; cursor spotlight; and a desktop
context menu.

## Constraints that stay

- **No hardcoded colour, font or size, QML included** — everything through
  `Config/Tokens.qml` and the `Config/*` layer.
- **Lock screen:** `ext-session-lock`, never a fullscreen window. The PAM
  result handling is the one security-critical path in this repo — simple,
  explicit, fail-closed. An ambiguous result is *not* authenticated, and
  nothing outside the `Success` branch may clear `locked`.
- **Motion categories** from the style tokens are binding. A heavy effect on a
  frequent event is a bug.
- Scrolling screen capture is permanently out of scope.
- The AI-agent panel talks only to `phi agent` and the local opencode HTTP
  API, never to opencode's on-disk files.

## Comments

Document the system, not the history. Say what a thing does and why a
non-obvious choice was made; do not record when it changed, what it used to
be, or which round changed it. Use `TODO:` for unfinished work and `FIXME:`
for a known bug, one line where possible.
