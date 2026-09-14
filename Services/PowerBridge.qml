pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Config as Config
import qs.Services as Services

// phiOS — thin wrapper over Quickshell.Services.UPower (S-23, master plan
// §8.1/§8.4: razer's battery anomaly-carrier module). The one file outside
// Config/ sanctioned to touch this service surface (phi-shell/CLAUDE.md).
//
// UPower.displayDevice ("an aggregate device and not a physical one",
// core.hpp's own doc comment) is real Quickshell source, not assumed —
// checked at git.outfoxxed.me/quickshell/quickshell, same practice as
// HyprlandBridge/AudioBridge. `percentage` is documented there as
// "equivalent to energy / energyCapacity" — a 0..1 fraction, not 0..100.
//
// UPower exposes no ready-made "%/hour" figure: `changeRate` is in watts
// (device.hpp gives it no unit doc, but UPower's own convention is power,
// not a percentage rate), the wrong unit for the razer threshold master
// plan §8.4 actually states ("scarica oltre 15%/ora"). Rather than guess a
// watts-to-percent conversion this file has no energyCapacity-independent
// way to verify, the rate is derived here from percentage itself, sampled
// on a plain timer — an approximation, but one built from the exact
// quantity the threshold is phrased in.

Singleton {
    id: root

    readonly property UPowerDevice device: UPower.displayDevice
    readonly property bool present: root.device !== null && root.device.isPresent && root.device.ready
    readonly property real percentage: root.present ? root.device.percentage : 0
    readonly property bool discharging: root.present && root.device.state === UPowerDeviceState.Discharging
    readonly property real timeToEmpty: root.present ? root.device.timeToEmpty : 0
    readonly property real timeToFull: root.present ? root.device.timeToFull : 0

    // Added at S-40 for the settings panel's General section (§9.12: "su
    // razer: statistiche batteria — autonomia, cicli, salute"). healthPercentage/
    // healthSupported are real UPowerDevice properties (confirmed against
    // real Quickshell source, services/upower/device.hpp, the same practice
    // every Services/ file in this repo follows) — healthSupported is false
    // on hardware/firmware that never reports a capacity baseline, in which
    // case the settings panel shows "not reported", never a fabricated number.
    readonly property real healthPercentage: root.present ? root.device.healthPercentage : 0
    readonly property bool healthSupported: root.present && root.device.healthSupported

    // Cycle count has no UPowerDevice property at all (device.hpp has none
    // — confirmed the same way, not guessed): upstream UPower's own D-Bus
    // ChargeCycles is exposed on some hardware/drivers and not others, and
    // Quickshell does not wrap it. Read directly via `upower -i`, the same
    // Quickshell.Io.Process pattern every CLI-probe Service in this repo
    // already uses (Tailscale, Config/Settings) — best-effort, "unknown"
    // when the line is absent (most laptops) rather than assuming -1 means
    // one specific thing.
    property string chargeCycles: "unknown"

    function refreshCycles() { cyclesProbe.running = true }
    Component.onCompleted: refreshCycles()

    Process {
        id: cyclesProbe
        onExited: cyclesProbe.running = false
        command: ["sh", "-c",
            "dev=$(upower -e 2>/dev/null | grep -m1 battery); [ -n \"$dev\" ] && upower -i \"$dev\" 2>/dev/null | awk -F': *' '/charge-cycles/{print $2; exit}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = this.text.trim()
                root.chargeCycles = (v.length > 0 && v !== "N/A") ? v : "unknown"
            }
        }
    }

    // %/hour, from the last ~10 minutes of samples while discharging.
    // Configurable, per the AGENT card's own instruction that these
    // placeholder thresholds must not be buried literals: a future
    // settings surface (not built here) has something real to bind to.
    property real dischargeRateThreshold: 15
    property real lowPercentThreshold: 0.20

    readonly property real dischargeRatePerHour: _dischargeRate()
    readonly property bool anomaly: root.present
        && (root.percentage < root.lowPercentThreshold
            || (root.discharging && root.dischargeRatePerHour > root.dischargeRateThreshold))

    property var samples: [] // [{t: Date.now(), pct: 0..1}, ...], oldest first

    function _dischargeRate() {
        if (root.samples.length < 2) return 0
        const first = root.samples[0]
        const last = root.samples[root.samples.length - 1]
        const hours = (last.t - first.t) / 3600000
        if (hours <= 0) return 0
        return Math.max(0, (first.pct - last.pct) * 100 / hours)
    }

    Timer {
        // A functional constant (how often to resample for the rate
        // estimate), not a design-system value — same category Clock.qml's
        // own 1000ms tick already flagged.
        interval: 60000
        running: root.present
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const next = root.samples.concat([{ t: Date.now(), pct: root.percentage }])
            // Keep ~10 minutes of history — enough for a stable per-hour
            // estimate without growing unbounded.
            root.samples = next.slice(Math.max(0, next.length - 10))
        }
    }

    // --- charging sound (docs/TODO.md: "add a sound on charging plugged
    // in", extended by "add customisation for sounds (battery sound)")
    // --------------------------------------------------------------------
    // On by default (unlike Services/Notifications.qml's own notification
    // sound, which defaults off) — this fires once per plug-in event, not
    // per-notification-burst, and the user asked for it directly rather
    // than this being a background feature someone would need to opt
    // into. "power-plug" is a real file in this project's own
    // sound-theme-freedesktop package — checked against the actual Arch
    // `extra` package file listing (archlinux.org/packages/extra/any/
    // sound-theme-freedesktop/files/), not recalled — and that package is
    // in profiles/desktop/packages.txt, so it is present wherever this
    // code runs (mini is headless, no phi-shell). Same theme/path,
    // `_soundPath()`/`playSound()` convention Services/Notifications.qml
    // already uses for its own sound (`name`/`volume`, not just on/off).
    //
    // Persistence: a JSON file (Config.Paths.powerSoundPrefsFile), not
    // `phi state` — see that path's own comment for why a value this
    // shape doesn't fit `phi state`'s closed scalar-key set. Was a single
    // `phi state` key (`power.chargingSound`) before `name`/`volume`
    // needed adding; `_migrateFromPhiState()` below reads that old key
    // exactly once, only when the new JSON file has never been written at
    // all, so a real "false" a user already set on a machine survives the
    // switch instead of silently reverting to the default "true".
    property bool chargingSoundEnabled: true
    property string chargingSoundName: "power-plug"   // freedesktop theme name, or an absolute path
    property int chargingSoundVolume: 100               // 0-100
    property string chargingSoundError: ""
    property bool _chargeSoundInit: false
    property bool _wasDischarging: false

    function setChargingSoundEnabled(b) { root.chargingSoundEnabled = !!b; root._persistSoundPrefs() }
    function setChargingSoundName(s) { root.chargingSoundName = String(s || "").trim(); root._persistSoundPrefs() }
    function setChargingSoundVolume(n) { root.chargingSoundVolume = Math.max(0, Math.min(100, Math.round(n))); root._persistSoundPrefs() }

    property bool _soundPrefsWritten: false
    function _persistSoundPrefs() {
        root._soundPrefsWritten = true
        soundPrefsFile.setText(JSON.stringify({
            enabled: root.chargingSoundEnabled,
            name: root.chargingSoundName,
            volume: root.chargingSoundVolume
        }, null, 2))
    }

    // Only reached from soundPrefsFile.onLoadFailed (FileNotFound — the
    // JSON file has never been written), so this never overwrites a real
    // preference the new file already holds. `Config.Settings.get` shells
    // out (tens of ms at least), so it's possible for the user to open
    // Settings and flip the toggle themselves before this callback lands —
    // the `_soundPrefsWritten` check means that real, fresh write always
    // wins instead of being silently reverted by a migration that started
    // first but finished second.
    function _migrateFromPhiState() {
        Config.Settings.get("power.chargingSound", (v, code) => {
            if (v === "false" && !root._soundPrefsWritten) {
                root.chargingSoundEnabled = false
                root._persistSoundPrefs()
            }
        })
    }

    Process {
        id: ensureStateDirProc
        command: ["mkdir", "-p", Config.Paths.stateDir]
        running: true
        onExited: ensureStateDirProc.running = false
    }

    FileView {
        id: soundPrefsFile
        path: Config.Paths.powerSoundPrefsFile
        watchChanges: false
        onLoaded: {
            try {
                const parsed = JSON.parse(soundPrefsFile.text())
                if (parsed && typeof parsed === "object") {
                    if (typeof parsed.enabled === "boolean") root.chargingSoundEnabled = parsed.enabled
                    if (typeof parsed.name === "string") root.chargingSoundName = parsed.name
                    if (typeof parsed.volume === "number") root.chargingSoundVolume = parsed.volume
                }
            } catch (e) {
                console.warn("phi-shell: power-sound.json failed to parse, ignoring: " + e)
            }
        }
        onLoadFailed: (error) => root._migrateFromPhiState()
    }

    // Plugged-in is detected as a discharging→not-discharging transition,
    // not a raw device.state read: `discharging` is already the vetted
    // derived property above (root.present && state === Discharging), so
    // this reuses it rather than re-deriving a second notion of "on AC"
    // from device.state directly. `_chargeSoundInit` exists so the FIRST
    // onDischargingChanged — which fires once UPower's displayDevice
    // becomes ready/present, regardless of which state it reports — never
    // itself counts as a transition and fires a spurious sound at shell
    // startup; it only starts comparing from the second change onward.
    // The `root.present` check on the trigger matters on real hardware:
    // `discharging` includes `root.present` in its own definition, so the
    // device disappearing entirely (a re-enumeration around suspend/
    // resume — this project has two open, unexplained hibernation bugs on
    // razer, the exact machine this targets) also reads as a
    // discharging→false transition. Without this check that would play
    // the "plugged in" sound on a suspend/resume cycle with no charger
    // event involved at all.
    onDischargingChanged: {
        if (!root._chargeSoundInit) {
            root._chargeSoundInit = true
            root._wasDischarging = root.discharging
            return
        }
        if (root._wasDischarging && !root.discharging && root.present) root.playChargingSound(false)
        root._wasDischarging = root.discharging
        root._evaluateBatterySaver()
    }
    onPercentageChanged: root._evaluateBatterySaver()

    // Resolve chargingSoundName to a filesystem path: an absolute path as
    // is, else a freedesktop sound-theme basename — same convention
    // Services/Notifications.qml's own `_soundPath()` uses.
    function _chargingSoundPath() {
        var n = root.chargingSoundName
        if (n.length === 0) return ""
        if (n.charAt(0) === "/") return n
        return "/usr/share/sounds/freedesktop/stereo/" + n + ".oga"
    }

    // `force` is set by the settings "Test sound" button so it plays even
    // while chargingSoundEnabled is false — same shape as
    // Services/Notifications.qml's own playSound(force).
    function playChargingSound(force) {
        if (!force && !root.chargingSoundEnabled) return
        if (chargeSoundProc.running) return
        var path = root._chargingSoundPath()
        if (path.length === 0) { root.chargingSoundError = "no sound file configured"; return }
        root.chargingSoundError = ""
        chargeSoundProc.command = ["pw-play", "--volume=" + (root.chargingSoundVolume / 100).toFixed(2), path]
        chargeSoundProc.running = true
    }

    Process {
        id: chargeSoundProc
        onExited: (exitCode) => {
            chargeSoundProc.running = false
            if (exitCode !== 0)
                root.chargingSoundError = "pw-play exited " + exitCode + " (is " + root._chargingSoundPath() + " present? sound-theme-freedesktop may not be installed)"
        }
    }

    // --- low-battery full-screen alert (docs/TODO.md: "full screen alert
    // should appear when battery level is low (2 thresholds warn and
    // danger, configurable)") --------------------------------------------
    // Deliberately separate from `lowPercentThreshold`/`anomaly` above:
    // those already drive Bar/modules/Battery.qml's icon colour (a
    // different, already-shipped surface with its own 0.20 default) — the
    // two thresholds here are net-new, own their own file, and changing
    // one must never silently move the other's meaning.
    property real alertWarnThreshold: 0.15
    property real alertDangerThreshold: 0.05

    function setAlertWarnThreshold(v) { root.alertWarnThreshold = Math.max(0, Math.min(1, v)); root._persistAlertPrefs() }
    function setAlertDangerThreshold(v) { root.alertDangerThreshold = Math.max(0, Math.min(1, v)); root._persistAlertPrefs() }

    property bool _alertPrefsWritten: false
    function _persistAlertPrefs() {
        root._alertPrefsWritten = true
        alertPrefsFile.setText(JSON.stringify({
            warnThreshold: root.alertWarnThreshold,
            dangerThreshold: root.alertDangerThreshold
        }, null, 2))
    }

    FileView {
        id: alertPrefsFile
        path: Config.Paths.batteryAlertPrefsFile
        watchChanges: false
        onLoaded: {
            try {
                const parsed = JSON.parse(alertPrefsFile.text())
                if (parsed && typeof parsed === "object") {
                    if (typeof parsed.warnThreshold === "number") root.alertWarnThreshold = parsed.warnThreshold
                    if (typeof parsed.dangerThreshold === "number") root.alertDangerThreshold = parsed.dangerThreshold
                }
            } catch (e) {
                console.warn("phi-shell: battery-alert.json failed to parse, ignoring: " + e)
            }
        }
        // No migration needed here (unlike soundPrefsFile above) — this is
        // a net-new preference, never a `phi state` scalar key. Absence
        // just means the defaults above stand.
    }

    // `testOverrideLevel` mirrors playChargingSound(force)'s testing
    // shape: Settings gets a "Test" action for each severity so the alert
    // can be exercised without actually draining a battery to 5% —
    // cleared the same moment the alert is dismissed, so a test never
    // outlives its own dialog.
    property string testOverrideLevel: "none" // "none" | "warn" | "danger"
    function testAlert(level) { root.dismissedLevel = "none"; root.testOverrideLevel = level }

    function _rank(level) { return level === "danger" ? 2 : (level === "warn" ? 1 : 0) }

    // Inlined rather than a called helper function, and explicitly gated
    // on Config.Capabilities.battery (mini has none) — the same capability
    // Devices.qml:274 and Bar/modules.json's battery row already gate on,
    // so this dialog can never fire on a machine with no battery even
    // though it's instantiated unconditionally in shell.qml.
    readonly property string alertLevel: {
        if (root.testOverrideLevel !== "none") return root.testOverrideLevel
        if (!Config.Capabilities.battery || !root.present || !root.discharging) return "none"
        if (root.percentage <= root.alertDangerThreshold) return "danger"
        if (root.percentage <= root.alertWarnThreshold) return "warn"
        return "none"
    }

    // The highest severity the user has already dismissed for the CURRENT
    // low-battery episode. `alertShown` compares by rank, not equality, so
    // an escalation (warn → danger) re-opens the alert even if warn was
    // already dismissed, but recovering (danger → warn) after a danger
    // dismissal stays quiet. Resets to "none" the moment the real level
    // returns to "none" (charged back up, or plugged in), so the NEXT
    // low-battery episode starts fresh rather than staying permanently
    // suppressed from one old dismissal.
    property string dismissedLevel: "none"
    readonly property bool alertShown: root._rank(root.alertLevel) > root._rank(root.dismissedLevel)

    function dismissAlert() {
        root.dismissedLevel = root.alertLevel
        root.testOverrideLevel = "none"
    }

    onAlertLevelChanged: {
        if (root.alertLevel === "none") root.dismissedLevel = "none"
    }

    // --- battery saving mode (docs/TODO.md: "have a battery saving mode,
    // it automatically kicks in when not in charge and lower then 20%
    // battery ... automatically disabled when plugged in and over the
    // threshold (if the user activates while it's charging, it should not
    // disable automatically, this flag is cleared once the charge is
    // plugged off again)") -------------------------------------------
    //
    // Reuses lowPercentThreshold (0.20 default, already this file's own
    // "<20% remaining" anomaly threshold above) rather than a second,
    // separate percentage field — the entry states this feature's own
    // threshold as a literal "20%" with no mention of it being settable,
    // unlike alertWarnThreshold/alertDangerThreshold above, which the
    // OTHER entry explicitly asked to be configurable; "configurable in
    // the settings panel" in THIS entry's own text reads as the
    // automation on/off switch below, not a second threshold field.
    //
    // Only batterySaverAuto (the automation switch) is persisted.
    // batterySaverActive and the charging-override flag are deliberately
    // session-local, recomputed fresh by _evaluateBatterySaver() every
    // time this singleton starts (called once the prefs file below
    // resolves) — a saved "was active" surviving a shell restart would
    // need to fabricate a reason it was on, when the real battery state at
    // the new startup already answers that question correctly on its own.
    //
    // The real saving actions: brightness is capped at 40%
    // (Services/Brightness.qml), restored to whatever it was the instant
    // saver turns off — never persisted anywhere, brightness is expected-
    // to-move hardware state, not a saved preference, so there is nothing
    // to lose across a restart. The lock screen's ambient effect is
    // suppressed as a READ-SIDE override: Lock/Lock.qml's effectLoader
    // gates on Services.PowerBridge.batterySaverActive directly, rather
    // than this file calling Config.LockPrefs.setEffect("none") — writing
    // through LockPrefs would permanently overwrite the user's actual
    // chosen effect in lock.json the moment a shell restart happened to
    // land while saver was active, with no reliable record left to
    // restore it from. Reading leaves the user's real choice untouched.
    property bool batterySaverAuto: true
    property bool batterySaverActive: false
    property bool _saverOverrideWhileCharging: false
    property int _brightnessBeforeSaver: -1
    property int _brightnessCapSetTo: -1

    function setBatterySaverAuto(b) {
        root.batterySaverAuto = !!b
        root._persistBatterySaverPrefs()
        root._evaluateBatterySaver()
    }

    // The manual switch — Panels/BarPopout.qml's battery card and the
    // settings panel both call this; nothing assigns batterySaverActive
    // directly, the same controlled-component shape every toggle in this
    // repo already follows.
    function setBatterySaverActive(b) {
        b = !!b
        if (b && !root.discharging) root._saverOverrideWhileCharging = true
        if (!b) root._saverOverrideWhileCharging = false
        root._applyBatterySaver(b)
    }

    function _applyBatterySaver(active) {
        if (active === root.batterySaverActive) return
        root.batterySaverActive = active
        if (active) {
            if (Services.Brightness.present) {
                root._brightnessBeforeSaver = Services.Brightness.percent
                root._brightnessCapSetTo = Math.min(Services.Brightness.percent, 40)
                Services.Brightness.set(root._brightnessCapSetTo)
            }
        } else {
            // Restore only if nothing has touched brightness since saver
            // capped it (brightness keys, the OSD and settings all go
            // through Services.Brightness.set(), the same setter this file
            // itself calls, so `percent` reflects any of them) — the user
            // may have deliberately raised or lowered it while saver was
            // active, and that choice must win, not be silently
            // overwritten back to whatever it was before saver started.
            if (root._brightnessBeforeSaver >= 0 && Services.Brightness.present
                    && Services.Brightness.percent === root._brightnessCapSetTo)
                Services.Brightness.set(root._brightnessBeforeSaver)
            root._brightnessBeforeSaver = -1
            root._brightnessCapSetTo = -1
        }
    }

    // Matches the entry's own state machine: auto-ON only while
    // discharging and at/under the threshold; auto-OFF only once plugged
    // in and over the threshold, UNLESS this activation was itself a
    // manual override made while charging — cleared the moment a real
    // discharge cycle starts (the entry's own "this flag is cleared once
    // the charge is plugged off again"), so the exemption only ever
    // protects the specific charging session it was set during.
    function _evaluateBatterySaver() {
        if (!root.present) return
        if (!root.discharging) {
            if (root.batterySaverActive && root.percentage > root.lowPercentThreshold && !root._saverOverrideWhileCharging)
                root._applyBatterySaver(false)
            return
        }
        if (root._saverOverrideWhileCharging) root._saverOverrideWhileCharging = false
        if (root.batterySaverAuto && !root.batterySaverActive && root.percentage <= root.lowPercentThreshold)
            root._applyBatterySaver(true)
    }

    // No _written guard like soundPrefsFile's own above: that one exists
    // because a phi-state migration can race a fresh write to the same
    // file. This file has no migration path (a net-new preference, same
    // as batteryAlertPrefsFile just above), so there is nothing for a
    // guard to arbitrate.
    function _persistBatterySaverPrefs() {
        batterySaverPrefsFile.setText(JSON.stringify({ auto: root.batterySaverAuto }, null, 2))
    }

    FileView {
        id: batterySaverPrefsFile
        path: Config.Paths.batterySaverPrefsFile
        watchChanges: false
        onLoaded: {
            try {
                const parsed = JSON.parse(batterySaverPrefsFile.text())
                if (parsed && typeof parsed === "object" && typeof parsed.auto === "boolean")
                    root.batterySaverAuto = parsed.auto
            } catch (e) {
                console.warn("phi-shell: battery-saver.json failed to parse, ignoring: " + e)
            }
            root._evaluateBatterySaver()
        }
        onLoadFailed: (error) => root._evaluateBatterySaver()
    }
}
