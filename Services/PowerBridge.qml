pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Config as Config
import qs.Services as Services


Singleton {
    id: root

    readonly property UPowerDevice device: UPower.displayDevice
    readonly property bool present: root.device !== null && root.device.isPresent && root.device.ready
    readonly property real percentage: root.present ? root.device.percentage : 0
    readonly property bool discharging: root.present && root.device.state === UPowerDeviceState.Discharging
    readonly property real timeToEmpty: root.present ? root.device.timeToEmpty : 0
    readonly property real timeToFull: root.present ? root.device.timeToFull : 0

    // healthSupported is false if hardware never reports a capacity baseline
    // — settings shows "not reported", not a fabricated value.
    readonly property real healthPercentage: root.present ? root.device.healthPercentage : 0
    readonly property bool healthSupported: root.present && root.device.healthSupported

    // No UPowerDevice property covers cycle count; read it via `upower -i` —
    // "unknown" when absent (most laptops).
    property string chargeCycles: "unknown"

    function refreshCycles() { cyclesProbe.running = true }
    Component.onCompleted: {
        refreshCycles()
        Config.Settings.get("bar.battery-percent", (v, code) => {
            if (v === "true") root.showPercentInBar = true
        })
    }

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
    property real dischargeRateThreshold: 15
    property real lowPercentThreshold: 0.20

    // Opt-in "80%" text label next to the bar icon.
    property bool showPercentInBar: false
    function setShowPercentInBar(v) {
        root.showPercentInBar = !!v
        Config.Settings.set("bar.battery-percent", v ? "true" : "false")
    }

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
        // Resample interval for rate estimate — a functional constant, not a
        // design token.
        interval: 60000
        running: root.present
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const next = root.samples.concat([{ t: Date.now(), pct: root.percentage }])
            // Keep ~10 minutes of history for a stable estimate without
            // unbounded growth.
            root.samples = next.slice(Math.max(0, next.length - 10))
        }
    }

    // --- charging sound --------------------------------------------------
    // On by default (unlike Notifications.qml). Persisted as JSON, not `phi
    // state`. _migrateFromPhiState() migrates the old `phi state` key once, so
    // an already-set "false" survives the switch instead of reverting to "true".
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

    // Only from soundPrefsFile.onLoadFailed, so never overwrites. _soundPrefsWritten
    // ensures fresh write beats a migration that started earlier but landed later.
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

    // Plugged-in: discharging→false transition, not raw state. _chargeSoundInit
    // skips first change to avoid spurious startup sound. root.present check
    // needed: device re-enumerating around suspend looks like discharging→false,
    // but without it we'd sound on resume with no charger.
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

    // Resolve chargingSoundName to filesystem path: absolute as is, else
    // freedesktop sound-theme basename (like Notifications.qml's _soundPath).
    function _chargingSoundPath() {
        var n = root.chargingSoundName
        if (n.length === 0) return ""
        if (n.charAt(0) === "/") return n
        return "/usr/share/sounds/freedesktop/stereo/" + n + ".oga"
    }

    // `force` lets "Test sound" play even when chargingSoundEnabled is false.
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

    // --- low-battery full-screen alert ------------------------------------
    // Separate from lowPercentThreshold: both drive Battery.qml's icon colour
    // independently, with different defaults.
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
        // No migration needed — this is a net-new preference, never a `phi
        // state` scalar key. Absence just means the defaults stand.
    }

    // Lets Settings exercise the alert without draining the battery; cleared
    // the moment the alert is dismissed.
    property string testOverrideLevel: "none" // "none" | "warn" | "danger"
    function testAlert(level) { root.dismissedLevel = "none"; root.testOverrideLevel = level }

    function _rank(level) { return level === "danger" ? 2 : (level === "warn" ? 1 : 0) }

    // Gated on Config.Capabilities.battery (mini has none) so alert never fires
    // on battery-less machines, even though instantiated unconditionally.
    readonly property string alertLevel: {
        if (root.testOverrideLevel !== "none") return root.testOverrideLevel
        if (!Config.Capabilities.battery || !root.present || !root.discharging) return "none"
        if (root.percentage <= root.alertDangerThreshold) return "danger"
        if (root.percentage <= root.alertWarnThreshold) return "warn"
        return "none"
    }

    // Highest severity dismissed for current episode. Compared by rank, so
    // escalation (warn→danger) re-opens alert, but recovery (danger→warn) stays
    // quiet. Resets when alert level clears.
    property string dismissedLevel: "none"
    readonly property bool alertShown: root._rank(root.alertLevel) > root._rank(root.dismissedLevel)

    function dismissAlert() {
        root.dismissedLevel = root.alertLevel
        root.testOverrideLevel = "none"
    }

    onAlertLevelChanged: {
        if (root.alertLevel === "none") root.dismissedLevel = "none"
    }

    // --- battery saving mode ----------------------------------------------
    // Reuses lowPercentThreshold as auto-enable threshold. Only batterySaverAuto
    // is user-configurable and persisted. batterySaverActive is session-local,
    // recomputed at startup. Brightness capped at 40%, restored on off.
    // Screensaver suppressed as read-side override (not Config.LockPrefs), so
    // restart won't overwrite the user's chosen effect.
    property bool batterySaverAuto: true
    property bool batterySaverActive: false
    property bool _saverOverrideWhileCharging: false
    // Without this, manual off while discharging at lowPercentThreshold would
    // be undone by the next update. Holds until charge cycle ends or battery
    // crosses warn threshold. Session-local only.
    property bool _saverSuppressedByUser: false
    property int _brightnessBeforeSaver: -1
    property int _brightnessCapSetTo: -1

    function setBatterySaverAuto(b) {
        root.batterySaverAuto = !!b
        root._persistBatterySaverPrefs()
        root._evaluateBatterySaver()
    }

    // Manual switch for future toggle UI; nothing calls this yet.
    function setBatterySaverActive(b) {
        b = !!b
        if (b && !root.discharging) root._saverOverrideWhileCharging = true
        if (!b) root._saverOverrideWhileCharging = false
        // Reuses alertWarnThreshold: if user turns off at/under lowPercentThreshold,
        // suppression holds until charge cycle ends or battery crosses warn threshold.
        if (!b && root.discharging && root.percentage <= root.lowPercentThreshold)
            root._saverSuppressedByUser = true
        if (b) root._saverSuppressedByUser = false
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
            // Restore only if brightness unchanged since cap — user may have
            // deliberately changed it while active.
            if (root._brightnessBeforeSaver >= 0 && Services.Brightness.present
                    && Services.Brightness.percent === root._brightnessCapSetTo)
                Services.Brightness.set(root._brightnessBeforeSaver)
            root._brightnessBeforeSaver = -1
            root._brightnessCapSetTo = -1
        }
    }

    // Auto-ON: discharging at/under threshold. Auto-OFF: plugged in over
    // threshold, unless manual override while charging (cleared on discharge).
    function _evaluateBatterySaver() {
        if (!root.present) return
        if (!root.discharging) {
            if (root.batterySaverActive && root.percentage > root.lowPercentThreshold && !root._saverOverrideWhileCharging)
                root._applyBatterySaver(false)
            // Charge ends the discharge session; next drop is a new episode.
            root._saverSuppressedByUser = false
            return
        }
        if (root._saverOverrideWhileCharging) root._saverOverrideWhileCharging = false
        if (root._saverSuppressedByUser && root.percentage <= root.alertWarnThreshold)
            root._saverSuppressedByUser = false
        if (root.batterySaverAuto && !root.batterySaverActive && root.percentage <= root.lowPercentThreshold
                && !root._saverSuppressedByUser)
            root._applyBatterySaver(true)
    }

    // No _written guard — no migration path exists for this preference.
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
