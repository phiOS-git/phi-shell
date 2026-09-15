pragma Singleton
import Quickshell
import Quickshell.Io
import qs.Services as Services

// phiOS — Services/SensorPermissions. docs/TODO.md: "add status bar icons
// for active sensors (microphone, camera); the overlay should show a list
// of apps with the sensor they are using and killswitches. Also add
// settings for killswitches and permission rules." + the entry's own
// **Answer:** "yes, the permission system must be built. It should be
// generally restrictive, always asking permission the first time an app
// requires it (granted once, always, or never)."
//
// UI-AND-INTERACTIONS ONLY, BY EXPLICIT INSTRUCTION (2026-09-15): the
// user asked for the full permission-system UI to be built now, with the
// real detection/enforcement mechanism designed and discussed separately
// afterward — this is not a gap found by this file, it is the agreed
// scope for this pass. The constraint that prompted that split: on a
// traditional (non-sandboxed) Linux desktop, there is no OS mechanism to
// block an ordinary app from opening a camera/mic device before it
// happens — that is what Flatpak + xdg-desktop-portal solve, and this
// system uses neither. A real implementation later would be a REACTIVE
// detect-then-kill loop (Pipewire capture-stream nodes for the
// microphone — Services/AudioBridge.qml already has the proven
// mechanism, see its `micInUse` — and /proc/*/fd scanning for
// `/dev/video*` for the camera, no precedent yet), not true prior
// restraint. Every function below that would need that detection is
// real Go/QML plumbing with an honest empty/no-op result today:
//   - `activeUsers` is always `[]` — nothing populates it yet.
//   - `requestPermission(appId, appName, sensor)` is real (sets
//     `pendingPrompt`, the dialog responds to it) but nothing calls it
//     automatically — Settings' own "send a test prompt" control is the
//     only caller today, clearly labelled as a UI preview.
//   - `killApp(pid)` really does send SIGTERM (Quickshell.Io.Process,
//     `kill <pid>`) — inert in practice only because `activeUsers` is
//     always empty, not because the call itself is fake.
// `rules` (the persisted always/never decisions) and `micEnabled`/
// `cameraEnabled` (the master per-sensor killswitches) are genuinely
// real and persist for the session — `micEnabled` bridges to
// Services.AudioBridge's real input-mute state; `cameraEnabled` is a
// session-local flag (moved here from a stray property that used to live
// directly on Panels/BarPopout.qml, no camera device backend exists to
// actually gate yet, same "no v4l2 precedent anywhere in this codebase"
// finding the interface rework's own write-up already recorded).

Singleton {
    id: root

    // --- master per-sensor killswitches -----------------------------------
    readonly property bool micEnabled: !Services.AudioBridge.inputMuted
    function setMicEnabled(v) { if (v !== root.micEnabled) Services.AudioBridge.toggleInputMute() }

    property bool cameraEnabled: true
    function setCameraEnabled(v) { root.cameraEnabled = v }

    // --- who's using what, right now --------------------------------------
    // { appId, appName, sensor: "microphone"|"camera", pid }[] — always
    // empty until a real detection service exists. See file header.
    readonly property var activeUsers: []

    function killApp(pid) {
        if (!pid || pid <= 0) return
        killProc.command = ["kill", String(pid)]
        killProc.running = true
    }
    Process { id: killProc }

    // --- stored per-app decisions ------------------------------------------
    // { appId, appName, sensor, decision: "always"|"never" }[] — "ask"
    // is not stored, it is the absence of a rule. Session-local (not
    // persisted to disk yet — a real detection pass will also need to
    // decide where these live, `phi state` or their own JSON file the
    // way Services/Vpn's config does; not decided here).
    property var rules: []

    function ruleFor(appId, sensor) {
        for (let i = 0; i < root.rules.length; i++) {
            const r = root.rules[i]
            if (r.appId === appId && r.sensor === sensor) return r
        }
        return null
    }

    function setRule(appId, appName, sensor, decision) {
        const existing = root.ruleFor(appId, sensor)
        const next = root.rules.filter(r => !(r.appId === appId && r.sensor === sensor))
        if (decision === "always" || decision === "never") {
            next.push({ appId: appId, appName: appName, sensor: sensor, decision: decision })
        }
        root.rules = next
    }

    function clearRule(appId, sensor) { root.setRule(appId, "", sensor, "ask") }

    // --- the permission prompt ---------------------------------------------
    // null | { appId, appName, sensor }. Dialogs/SensorPermissionPrompt.qml
    // shows itself whenever this is non-null.
    property var pendingPrompt: null

    // Not exposed outside this file — respond() reads it, same "caller
    // can never be left with a stale reference" reasoning
    // Services/ConfirmDialog.qml's own `_onConfirm` already uses.
    property var _onAnswered: null

    // The one real, callable entry point a future detection service would
    // use — see file header for why nothing calls it automatically yet.
    // callback(allowed: bool) — called synchronously if a stored
    // "always"/"never" rule already answers this appId+sensor, or later
    // via respond() once the user picks one of the dialog's three
    // choices. Matches Services/ConfirmDialog.qml's own open()-takes-a-
    // callback shape rather than inventing a sync-or-async return value.
    function requestPermission(appId, appName, sensor, callback) {
        const existing = root.ruleFor(appId, sensor)
        if (existing) {
            if (callback) callback(existing.decision === "always")
            return
        }
        root.pendingPrompt = { appId: appId, appName: appName, sensor: sensor }
        root._onAnswered = callback || null
    }

    // Settings' own "preview the permission prompt" control — always
    // shows the dialog, ignoring any stored rule, so a repeated preview
    // click keeps working even after the user has picked "Always"/"Never"
    // once. requestPermission() itself must never skip its own rule
    // check (that IS the point, for a real caller) — this is a distinct
    // function specifically so that real behaviour never has to bend for
    // a test affordance's convenience.
    function previewPrompt(sensor) {
        root.pendingPrompt = { appId: "preview", appName: "Test App", sensor: sensor }
        root._onAnswered = null
    }

    // decision: "once" | "always" | "never" — matches the TODO's own
    // "granted once, always, or never". "always"/"never" also persist a
    // rule; "once" answers only this one request.
    function respond(decision) {
        const p = root.pendingPrompt
        const cb = root._onAnswered
        root.pendingPrompt = null
        root._onAnswered = null
        if (!p) return
        if (decision === "always" || decision === "never") {
            root.setRule(p.appId, p.appName, p.sensor, decision)
        }
        if (cb) cb(decision === "always" || decision === "once")
    }
}
