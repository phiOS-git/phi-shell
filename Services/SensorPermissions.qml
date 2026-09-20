pragma Singleton
import Quickshell
import Quickshell.Io
import qs.Services as Services

// UI and interactions only — the real detection/enforcement mechanism is
// separate future work, not a gap in this file. On a traditional
// (non-sandboxed) Linux desktop there is no OS mechanism to block an
// ordinary app from opening a camera/mic device before it happens; that
// needs Flatpak + xdg-desktop-portal, which this system uses neither of.
// A real implementation would be a reactive detect-then-kill loop
// (Pipewire capture-stream nodes for the microphone — Services/
// AudioBridge.qml's `micInUse` already has the mechanism — and
// /proc/*/fd scanning for /dev/video* for the camera, no precedent yet)
// not true prior restraint. What's below is honest about which parts are
// real:
// - `activeUsers` is always `[]` — nothing populates it yet.
// - `requestPermission(appId, appName, sensor)` is real (sets
// `pendingPrompt`, the dialog responds to it) but nothing calls it
// automatically — Settings' own "send a test prompt" control is the
// only caller today, clearly labelled as a UI preview.
// - `killApp(pid)` really does send SIGTERM — inert in practice only
// because `activeUsers` is always empty, not because the call is fake.
// `rules` (persisted always/never decisions) and `micEnabled`/
// `cameraEnabled` (the master per-sensor killswitches) are genuinely
// real: `micEnabled` bridges to Services.AudioBridge's real input-mute
// state; `cameraEnabled` is a session-local flag — no camera device
// backend exists yet to actually gate.

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
    // { appId, appName, sensor, decision: "always"|"never" }[] — "ask" is
    // not stored, it's the absence of a rule. Session-local, not yet
    // persisted to disk.
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
