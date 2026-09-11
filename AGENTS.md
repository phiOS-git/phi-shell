# phi-shell — the desktop shell

QML on Quickshell 0.3.1. One shell process for the whole session — bar,
panels, launcher, lock screen, settings, notifications, overview,
screenshot, magnifier, OSD — not a set of independent components.

**You cannot run this.** Every visual result is verified by the user with a
screenshot.

Part of the phiOS workspace. The workspace `AGENTS.md` (one level up, or in
`docs/archive/` of a standalone clone) carries the rules for every
repository — **branch locally, only `main`/`dev` on the remote; only
official Arch packages; the user owns releases, an agent only tags; no
secrets in a public repo; design tokens are the only source of colour,
font and size.** Not repeated here.

When your work matches an entry in the workspace's `docs/TODO.md`, claim it
with `[taken]` and report the result in `docs/VERIFICATION.md` — see *The
TODO / VERIFICATION loop* in the workspace `AGENTS.md`. A shell change needs
a screenshot from the user, so its test steps must say exactly what to look
at and what changed.

## Running it

Clone to exactly `~/.config/quickshell/phi` (Quickshell keys config by
folder name). Hyprland starts `qs -p ~/.config/quickshell/phi` on login.
Quickshell hot-reloads every loaded file on save, so editing a `.qml` file
needs no restart. A fresh process is only needed for a broken state or to
watch stdout: `pkill -x qs; qs -p ~/.config/quickshell/phi`.

## How this repo is built

- **`Config/Tokens.qml` is generated** by `phi theme` (from
  `phios-dotfiles/design/adapters.txt`) and is gitignored. Never edit it,
  never commit a hand-written copy. `Config/Tokens.example.qml` is the
  checked-in worked example. Render once with `phi theme set dark` before
  the first run.
- **The service surface is fenced off.** `Config/Appearance.qml`,
  `Config/Capabilities.qml` and the files under `Services/` are the only
  places that touch `Quickshell.Services.*`, `.Hyprland`, `.Wayland`,
  `.Bluetooth`, `.Networking` — the API Quickshell does not keep stable at
  0.3.x. Everything else reads one of those. Each `Services/*.qml` is a
  thin re-export of exactly what its consumers need, no logic. (The
  `Singleton` base class and `Quickshell.Io` — `Process`, `FileView` — are
  foundational and used wherever a file legitimately bridges to an external
  process.)
- **Type is code, instance is data (ADR 078).** A bar module, a panel tab
  or a settings section is written once as a component; the instance is a
  row in `Bar/modules.json`, `Panels/tabs.json` or `Settings/sections.json`.
  Adding one must be a one-file data change — if it is not, the design is
  wrong.
- **Capability-gated (ADR 074).** A module declares a capability
  requirement and appears only where `Config/Capabilities.qml` reports it.
  The shell never asks "am I a laptop".
- **N monitors from day one (ADR 077).** One monitor today is not a reason
  to hardcode one.

## Constraints that stay

- **No hardcoded colour, font or size, QML included** — everything through
  `Config/Tokens.qml` and the `Config/*` layer. This is enforced by audit.
- **Lock screen:** `ext-session-lock` protocol, never a fullscreen window.
  The PAM result handling is the one security-critical path — simple,
  explicit, fail-closed. An ambiguous result is *not authenticated*.
- **Motion categories** (from the style tokens) are binding. A heavy effect
  on a frequent event is a bug.
- Scrolling screen capture is permanently out of scope.
- The AI-agent panel talks only to `phi agent` and the local opencode HTTP
  API — never to opencode's on-disk files.

## Releasing

Tag `vX.Y.Z` on `main` and push the tag. The user builds and publishes the
signed `phi-shell` package from `phi-packages`.
