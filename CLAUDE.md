# phi-shell — desktop shell

QML on Quickshell 0.3.x. **You cannot run this.** Every visual result is verified by the user with a screenshot.

- Quickshell's API is not stable at 0.3.x. `Config/Appearance.qml` and `Config/Capabilities.qml` are the only files that touch the *service* surface — `Quickshell.Services.*`, `.Hyprland`, `.Wayland`, `.Bluetooth`, `.Networking` — the part master plan §8.1 actually flags as unstable at 0.3.x. Everything else reads those two for that surface, never importing it directly. This does **not** cover the `Singleton` base class (every singleton must inherit it, S-20) or `Quickshell.Io` (`Process`, `FileView`): that is foundational, stable plumbing, used wherever a file legitimately bridges to an external process or file — `Config/Settings.qml`'s `phi state` bridge, `Services/Clipboard.qml` (S-32), the hyprsunset control call (S-42), and others as they land. Decided at S-20 after checking the roadmap: those later steps already plan `Quickshell.Io` usage outside Config/, so the strict reading could not have held.
- `Config/Tokens.qml` is **generated** by `phi theme`. Never edit it; never commit a hand-written version.
- ADR 078: the *type* of a bar module or sidebar tab is code, written once. The *instance* is a row in `Bar/modules.json` or `Panels/tabs.json`. Adding a module must be a one-file data change — if it is not, the design is wrong.
- ADR 074: modules declare a capability requirement and appear only where it exists. The shell never asks "am I a laptop".
- ADR 077: designed for N monitors from day one. One monitor today is not a reason to hardcode one.
- Lock screen: use the `ext-session-lock` protocol, never a fullscreen window. The PAM result handling is the only genuinely security-critical code here — keep it simple, explicit, and fail-closed. An ambiguous result is *not authenticated*.
- Motion categories are in the style plan §5 and are binding. A category-C effect on a frequent event is a bug.
