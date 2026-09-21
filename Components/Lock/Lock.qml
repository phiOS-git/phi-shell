import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pam
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "screensavers" as Screensavers
import "." as LockLocal
import "../Dialogs" as Dialogs

// The lock surface. The session-stays-locked guarantee comes from the
// ext-session-lock PROTOCOL, not this file: if WlSessionLock dies or
// Quickshell exits without clearing `locked`, a conformant compositor leaves
// the output locked and painted. Never substitute a fullscreen window for it.
//
// The PamContext.completed handler below is the only security-critical code in
// this shell. PamResult has four values; exactly one branch unlocks (Success),
// the default covers Failed/Error/MaxTries and anything unanticipated.
// Ambiguous is not authenticated. Unlocking has no IPC path — `locked` is
// cleared only from that Success branch. Locking does have one, which is
// harmless.
//
// PamContext is declared once, outside `surface`: WlSessionLock instantiates
// `surface` per screen, so declaring it inside would open a concurrent PAM
// conversation per monitor. WlSessionLock's default property `surface` is a
// singular QQmlComponent, not a list, so every other child must be assigned to
// a named property or it competes for that slot — that once broke `ipc call
// lock lock`.
//
// /etc/pam.d/phi-shell-lock is /etc material this repo never applies. Until
// the user installs it, PamContext.start() fails with StartFailed, another
// non-Success case: fail-closed holds even before setup.

WlSessionLock {
    id: root

    property int attempts: 0
    property string errorText: ""

    // True from submit until PAM answers; cleared only by the `pam.completed`
    // and `pam.error` handlers. pam_unix takes ~2s per attempt (memory-hard
    // hash), so the wait is visible: the field shows "Verifying…" and pulses.
    property bool validating: false

    // Additive on top of the fail-closed switch — it never touches the Success
    // branch. Enough consecutive failures disable the field and show a
    // countdown instead of letting retryTimer open a fresh PAM conversation
    // each time. 5 attempts / 30s cooldown is a plain OS convention.
    readonly property int lockoutThreshold: 5
    readonly property int lockoutSeconds: 30
    property bool lockedOut: false
    property int lockoutRemaining: 0
    // 1 → 0 as the lockout cooldown drains, fed by the 1s countdown below —
    // the timer made arithmetic, so the field's drain bar and any screensaver
    // reaction can draw the countdown without knowing PAM.
    readonly property real lockoutProgress: root.lockoutSeconds > 0
        ? root.lockoutRemaining / root.lockoutSeconds : 0

    Timer {
        id: lockoutCountdown
        interval: 1000
        repeat: true
        running: root.lockedOut
        onTriggered: {
            root.lockoutRemaining -= 1
            if (root.lockoutRemaining <= 0) {
                root.lockedOut = false
                root.attempts = 0
                root.errorText = ""
                if (root.locked) root.pam.start()
            }
        }
    }

    // Set true only in the Success branch, reset false at every lock. It is
    // the conceal transition's trigger; LockTransition's conceal-finished
    // handler is what actually clears `locked`.
    //
    // The reset is load-bearing and fail-closed: unlock fires on the RISING
    // edge (onAuthenticatedChanged). Without it, a second lock starts with
    // `authenticated` still true, so the next Success changes nothing, emits
    // no signal, and the screen stays locked on a correct password. Writing
    // false can only keep a screen locked, never open one.
    property bool authenticated: false

    // No `id:` on these three — a bare id matching a property name on the same
    // object is a real ambiguity class. Everything below uses `root.pam` /
    // `root.retryTimer` explicitly.
    property PamContext pam: PamContext {
        config: "phi-shell-lock"
    }

    // Emitted for every completed attempt, success or failure, so a
    // screensaver that opts in (Plasma's validation wave) can react to either.
    // Paints only, but emitted at the handshake boundary so the receiver sees
    // the true result.
    signal validationAttempt(bool success)

    // The user's name, from the environment (the same USER env read
    // BarPopout's status card already makes) — never a hardcoded account name
    // or a literal "user".
    readonly property string user: Quickshell.env("USER") || "there"
    // Time-of-day greeting, bracketed by the lock hit at the hour. The locked
    // screen only ever re-evaluates this on the per-second clock tick, and the
    // wording only visibly changes at a bracket boundary.
    function greetingFor(now) {
        var h = now.getHours()
        if (h >= 5 && h < 12) return "Good morning"
        if (h >= 12 && h < 18) return "Good afternoon"
        if (h >= 18 && h < 22) return "Good evening"
        return "Good night"
    }

    // Notifications that arrived while this lock has been active, newest
    // first, capped. Source and time only — no summary or body, so a peek at a
    // locked screen leaks nothing. Fed by the `arrived` signal, which carries
    // its own timestamp; no live Notification object is retained.
    property var lockNotifications: []
    readonly property int lockNotificationsMax: 4
    property real lockStartedAt: 0
    // Property-assigned child, NOT a bare positional one: WlSessionLock's
    // singular `surface` default property would otherwise claim it — the exact
    // failure the header above documents.
    property Connections notificationsConnection: Connections {
        target: Services.Notifications
        function onArrived(entry) {
            if (root.locked && root.lockStartedAt > 0 && entry
                    && (entry.timestamp || 0) >= root.lockStartedAt) {
                root.lockNotifications = [entry]
                    .concat(root.lockNotifications)
                    .slice(0, root.lockNotificationsMax)
            }
        }
    }

    Component.onCompleted: {
        root.pam.completed.connect((result) => {
            // The PAM conversation has ended — whatever the outcome, the
            // validating state must clear; only success/failure branches below
            // decide what comes next.
            root.validating = false
            // Broadcast the outcome first — the screensaver pulse needs the
            // raw result, and nothing about the unlock below depends on it.
            // See the `validationAttempt` property comment.
            root.validationAttempt(result === PamResult.Success)
            if (result === PamResult.Success) {
                // Starts the conceal; LockTransition's conceal-finished
                // handler clears `root.locked`. See the `authenticated`
                // comment for why unlock is routed through the animation.
                root.authenticated = true
                return
            }
            root.attempts += 1
            root.errorText = PamResult.toString(result)
            if (root.attempts >= root.lockoutThreshold) {
                root.lockedOut = true
                root.lockoutRemaining = root.lockoutSeconds
                // No retryTimer restart here — a fresh PAM conversation only
                // starts again once the countdown above reaches zero.
            } else if (root.locked) {
                root.retryTimer.restart()
            }
        })
        // Without this retry a start-time failure (StartFailed — e.g. the
        // pam.d file not installed) is terminal: PamContext never fires
        // `completed`, so `retryTimer` never restarts and nothing recovers.
        // Retrying picks up a fix applied from outside.
        //
        // Deliberately a separate, slower timer than `retryTimer` (600ms, for
        // a human retyping): an unattended config fault would otherwise call
        // pam.start() every 600ms forever, and pam_faillock-style modules
        // count start attempts — turning a config mistake into a locked
        // account.
        root.pam.error.connect((err) => {
            root.validating = false
            root.errorText = PamError.toString(err)
            if (root.locked) root.errorRetryTimer.restart()
        })
    }

    property Timer retryTimer: Timer {
        interval: 600
        onTriggered: if (root.locked) root.pam.start()
    }

    // See the `error.connect` comment above for why this is separate from, and
    // much slower than, `retryTimer`.
    property Timer errorRetryTimer: Timer {
        interval: 5000
        onTriggered: if (root.locked) root.pam.start()
    }

    // Locking only. See this file's own header for why unlocking has no IPC
    // counterpart.
    property IpcHandler lockIpc: IpcHandler {
        target: "lock"
        function lock(): void {
            root.attempts = 0
            root.errorText = ""
            root.validating = false
            root.lockedOut = false
            root.lockoutRemaining = 0
            // A fresh timestamp and an empty list: the notification area only
            // ever shows what arrived since THIS lock began.
            root.lockStartedAt = Date.now()
            root.lockNotifications = []
            // Per-lock reset — see the `authenticated` property comment for
            // why a stale `true` here would make this lock un-unlockable.
            root.authenticated = false
            root.locked = true
            // Services/LockState.qml's own header on why the matching
            // false-write lives in the LockTransition conceal-finished handler
            // below, not here.
            Services.LockState.locked = true
            root.pam.start()
        }
    }

    surface: Component {
    WlSessionLockSurface {
        id: surface

        color: Config.Appearance.background

        // Set by the first key press, click or pointer movement; reveals the
        // password field (see passwordGate).
        property bool inputSeen: false
        property point _pointerStart: Qt.point(-1, -1)

        // passwordField is always enabled, so it can take focus as soon as the
        // surface exists. One per screen; only one is input-focused at a time.
        Component.onCompleted: {
            passwordField.forceActiveFocus()
            // The reveal is deferred one turn (Qt.callLater) so the surface is
            // mapped when the animation starts. Without it the transition ran
            // off-screen and read as instant.
            Qt.callLater(function () { transition.reveal() })
        }

        // Forwards a completed attempt's outcome to the active screensaver if
        // it opted into the validation contract (only Plasma declares it).
        function _pulseScreensaver(success) {
            var fx = effectLoader.item
            if (fx && typeof fx.triggerValidation === "function") fx.triggerValidation(success)
        }

        // Plain system actions — none touch PAM or `root.locked`, so this does
        // not weaken the security path: a locked screen that reboots is locked
        // until the reboot happens. Reboot/shutdown still confirm first.
        function choosePower(action) {
            if (Services.PowerActions.needsConfirm(action)) {
                Services.ConfirmDialog.open({
                    title: Services.PowerActions.title(action),
                    message: "This cannot be undone.",
                    confirmLabel: Services.PowerActions.title(action),
                    onConfirm: () => Services.PowerActions.perform(action)
                })
            } else {
                Services.PowerActions.perform(action)
            }
        }

        TextMetrics {
            id: chMetrics
            font.family: Config.Appearance.fontMono
            font.pixelSize: Config.Appearance.fontSize1
            text: "0"
        }
        readonly property real chWidth: chMetrics.width

        // One mono cell at the password field's own size — the block caret
        // below is exactly this wide and tall, the fixed-cell terminal cursor.
        TextMetrics {
            id: fieldCell
            font.family: Config.Appearance.fontMono
            font.pixelSize: Config.Appearance.fontSize2
            text: "0"
        }

        // Block-caret blink: hard on/off at half the tracking period, only
        // while the field has focus. Paused during `validating`, when the
        // caret pulses instead.
        QtObject { id: caret; property bool on: true }
        Timer {
            id: caretBlink
            interval: Config.Appearance.motionAPeriod / 2
            running: passwordField.activeFocus && !root.validating
            repeat: true
            onTriggered: caret.on = !caret.on
        }

        // Validation pulse: soft in/out on the field border while
        // `validating`. The ~2s PAM wait must read as processing, not a dead
        // screen. Category A; suppressed under battery saver, though the
        // static "Verifying…" stays.
        property real validationPulse: 0.0
        SequentialAnimation on validationPulse {
            running: root.validating && !Services.PowerBridge.batterySaverActive
            loops: Animation.Infinite
            NumberAnimation {
                to: 1.0
                duration: Config.Appearance.motionAPeriod / 2
                easing.type: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad
            }
            NumberAnimation {
                to: 0.0
                duration: Config.Appearance.motionAPeriod / 2
                easing.type: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad
            }
        }

        // The content fades in on appear and back out on successful unlock.
        // The surface's own opaque `color` never animates — ext-session-lock
        // requires a locked output to stay painted — so this inner layer
        // carries the whole transition. The movement lives in
        // LockTransition.qml; this file only wires reveal, conceal, and the
        // conceal-finished clear of `locked`.
        LockLocal.LockTransition {
            id: transition
            anchors.fill: parent

            // The first hover point is where the pointer already was when the
            // surface mapped; only movement past a small tolerance counts.
            HoverHandler {
                onPointChanged: {
                    const p = point.position
                    if (surface._pointerStart.x < 0) { surface._pointerStart = p; return }
                    if (Math.abs(p.x - surface._pointerStart.x) + Math.abs(p.y - surface._pointerStart.y)
                            > Config.Appearance.fontSize1)
                        surface.inputSeen = true
                }
            }
            PointHandler { onActiveChanged: if (active) surface.inputSeen = true }
            // Blocks of the centred column in reveal order; each owns an
            // opacity and small-rise cascade on category B over the envelope.
            // The notification area is deliberately excluded — it is empty at
            // reveal and appears on its own.
            targets: [greetingText, clockText, dateText, statusBlock, passwordPanel, errorText, powerBlock]
            // Same read-side gate the screensaver Loader below is suppressed
            // under: while the system is in low-power mode every lock/unlock
            // movement collapses to an instant snap.
            animated: !Services.PowerBridge.batterySaverActive

            // Screensaver backdrop, behind everything; the effect is chosen in
            // Settings → Theme via Config.LockPrefs. Every effect exposes
            // `running`, bound here so it freezes when the conceal starts.
            // Suppressed under battery saver as a READ-SIDE override only —
            // the user's stored choice is never rewritten.
            Loader {
                id: effectLoader
                anchors.fill: parent
                z: -1
                active: Config.LockPrefs.effect !== "none" && !Services.PowerBridge.batterySaverActive
                sourceComponent: {
                    switch (Config.LockPrefs.effect) {
                    case "lava": return lavaFx
                    case "matrix": return matrixFx
                    case "starfield": return starFx
                    case "plasma": return plasmaFx
                    case "life": return lifeFx
                    case "boids": return boidsFx
                    default: return null
                    }
                }
                onLoaded: if (item) item.running = Qt.binding(function () { return !root.authenticated })
            }

            // `overlayScrim`, not the `Strong` variant: at that weight it
            // crushed every screensaver to nothing (most already draw at low
            // intensity). Sits above the screensaver (z: -1) and below the
            // readable content, so clock/field/pills keep full contrast while
            // the backdrop reads calmer.
            Rectangle {
                anchors.fill: parent
                color: Config.Appearance.overlayScrim
            }
            // speed is shared across effects; intensityFor(key) and
            // paramFor(key, name, default) are per-effect. Each default
            // matches that effect's own file-level default, so an untouched
            // key renders identically.
            Component { id: lavaFx; Screensavers.LavaLamp {
                speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("lava")
                blobCount: Config.LockPrefs.paramFor("lava", "blobCount", 9)
                wobble: Config.LockPrefs.paramFor("lava", "wobble", 1.0)
                validating: root.validating; validationProgress: validationPulse
                lockedOut: root.lockedOut; lockoutProgress: root.lockoutProgress
            } }
            Component { id: matrixFx; Screensavers.MatrixRain {
                speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("matrix")
                density: Config.LockPrefs.paramFor("matrix", "density", 1.0)
                validating: root.validating; validationProgress: validationPulse
                lockedOut: root.lockedOut; lockoutProgress: root.lockoutProgress
            } }
            Component { id: starFx; Screensavers.Starfield {
                speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("starfield")
                starCount: Config.LockPrefs.paramFor("starfield", "starCount", 140)
                validating: root.validating; validationProgress: validationPulse
                lockedOut: root.lockedOut; lockoutProgress: root.lockoutProgress
            } }
            Component { id: plasmaFx; Screensavers.Plasma {
                speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("plasma")
                resolution: Config.LockPrefs.paramFor("plasma", "resolution", 1.0)
                validating: root.validating; validationProgress: validationPulse
                lockedOut: root.lockedOut; lockoutProgress: root.lockoutProgress
            } }
            Component { id: lifeFx; Screensavers.Life {
                speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("life")
                resolution: Config.LockPrefs.paramFor("life", "resolution", 1.0)
                seedDensity: Config.LockPrefs.paramFor("life", "seedDensity", 0.28)
                validating: root.validating; validationProgress: validationPulse
                lockedOut: root.lockedOut; lockoutProgress: root.lockoutProgress
            } }
            Component { id: boidsFx; Screensavers.Boids {
                speed: Config.LockPrefs.speed; intensity: Config.LockPrefs.intensityFor("boids")
                boidCount: Config.LockPrefs.paramFor("boids", "boidCount", 40)
                validating: root.validating; validationProgress: validationPulse
                lockedOut: root.lockedOut; lockoutProgress: root.lockoutProgress
            } }

            // New-notification area: entries since this lock began, source and
            // time only, in the same mono grammar as the bar's history rows.
            // Anchored to the top on purpose so the centred auth column never
            // shifts.
            Item {
                id: notificationBlock
                anchors.top: parent.top
                anchors.topMargin: surface.chWidth * Config.Appearance.space4
                anchors.horizontalCenter: parent.horizontalCenter
                width: surface.chWidth * 40
                height: notificationColumn.implicitHeight + notificationPanel.padding * 2
                opacity: root.lockNotifications.length > 0 ? 1 : 0
                visible: opacity > 0
                // Appears (and disappears) with a quick category-B fade — a
                // state transition, not a motion category-A pulse.
                Behavior on opacity {
                    NumberAnimation {
                        duration: Config.Appearance.motionBDuration
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Config.Appearance.motionBCurve
                    }
                }

                Widgets.Panel {
                    id: notificationPanel
                    anchors.fill: parent
                    // Same low-contrast terminal edge as the password field —
                    // a subtle surface, not a loud card.
                    radius: Config.Appearance.radiusSmall
                    borderColorOverride: Config.Appearance.border
                    borderWidthOverride: Config.Appearance.borderWidth

                    Column {
                        id: notificationColumn
                        width: parent.width
                        spacing: surface.chWidth * Config.Appearance.space1
                        Repeater {
                            model: root.lockNotifications
                            delegate: Item {
                                required property var modelData
                                width: notificationColumn.width
                                implicitHeight: Math.max(sourceText.implicitHeight, timeText.implicitHeight)
                                Widgets.StyledText {
                                    id: sourceText
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: timeText.left
                                    anchors.rightMargin: surface.chWidth * Config.Appearance.space2
                                    kind: "label"
                                    mono: true
                                    sizeStep: 0
                                    elide: Text.ElideRight
                                    text: modelData.appName && modelData.appName.length > 0
                                        ? modelData.appName : "(unknown)"
                                }
                                Widgets.StyledText {
                                    id: timeText
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    kind: "label"
                                    mono: true
                                    sizeStep: 0
                                    text: Qt.formatTime(new Date(modelData.timestamp), "HH:mm")
                                }
                            }
                        }
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: surface.chWidth * Config.Appearance.space4
                width: surface.chWidth * 44

                Widgets.StyledText {
                    id: greetingText
                    anchors.horizontalCenter: parent.horizontalCenter
                    kind: "label"
                    mono: true
                    // Time-of-day greeting (by hour bracket) + the user's name
                    // — both derived at runtime, never hardcoded.
                    text: root.greetingFor(clockTick.now) + ", " + root.user
                }
                Widgets.ScrambleText {
                    id: clockText
                    // Resolves once when the surface first appears — a rare
                    // event. Subsequent per-second ticks just update the text,
                    // never re-scrambling.
                    anchors.horizontalCenter: parent.horizontalCenter
                    sizeStep: 6
                    mono: true
                    finalText: Qt.formatTime(clockTick.now, "hh:mm")
                }
                Widgets.StyledText {
                    id: dateText
                    anchors.horizontalCenter: parent.horizontalCenter
                    kind: "label"
                    text: Qt.formatDate(clockTick.now, "dddd, d MMMM")
                }

                Item {
                    id: statusBlock
                    width: parent.width
                    height: statusRow.implicitHeight
                    visible: Services.PowerBridge.present || (Services.Mpris.active !== null)

                    Row {
                        id: statusRow
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: surface.chWidth * Config.Appearance.space3

                        Widgets.BatteryIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Services.PowerBridge.present
                            // Light text on the lock's dark scrim — the
                            // opposite-contrast token.
                            iconColor: Config.Appearance.colorOpposite
                            fillColor: Config.Appearance.colorOpposite
                            level: Services.PowerBridge.percentage
                            chargingAmount: Services.PowerBridge.discharging ? 0 : 1
                            // The saver hatch: the state that collapses the
                            // transition and suppresses the screensaver, so
                            // the icon explains why the background went still.
                            saverAmount: Services.PowerBridge.batterySaverActive ? 1 : 0
                            sizeStep: 2
                            Behavior on level {
                                NumberAnimation {
                                    duration: Config.Appearance.motionBDuration
                                    easing.type: Easing.Bezier
                                    easing.bezierCurve: Config.Appearance.motionBCurve
                                }
                            }
                        }
                        Widgets.StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            kind: "label"
                            mono: true
                            visible: Services.PowerBridge.present
                            text: Math.round(Services.PowerBridge.percentage * 100) + "% "
                                + (Services.PowerBridge.discharging ? "discharging" : "charging")
                        }
                        Widgets.StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            kind: "label"
                            visible: Services.Mpris.active !== null
                            text: Services.Mpris.active !== null
                                ? (Services.Mpris.active.trackArtist + " — " + Services.Mpris.active.trackTitle)
                                : ""
                        }
                    }
                }

                // Pre-input state: the field stays hidden, though focused so the
                // first keystroke still types, until a key press, a click or a
                // real pointer movement on this screen.
                Item {
                    id: passwordGate
                    width: parent.width
                    height: passwordPanel.height
                    opacity: surface.inputSeen ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                    }

                    Widgets.Panel {
                        id: passwordPanel
                        width: parent.width
                        height: passwordField.implicitHeight + padding * 2
                        // A terminal input has a hard edge, not a rounded card —
                        // the sharpest radius the grammar carries.
                        radius: Config.Appearance.radiusSmall
                        // Panel's default border is loud, like a settings card —
                        // wrong here, where nothing else is boxed. Softened to the
                        // low-contrast border pair. `invalid` is untouched, so a
                        // real error stays full strength. While `validating` the
                        // override lerps border→borderStrong on the category-A
                        // pulse.
                        borderColorOverride: root.validating
                            ? Qt.rgba(
                                Config.Appearance.border.r
                                    + (Config.Appearance.borderStrong.r - Config.Appearance.border.r) * validationPulse,
                                Config.Appearance.border.g
                                    + (Config.Appearance.borderStrong.g - Config.Appearance.border.g) * validationPulse,
                                Config.Appearance.border.b
                                    + (Config.Appearance.borderStrong.b - Config.Appearance.border.b) * validationPulse,
                                Config.Appearance.border.a
                                    + (Config.Appearance.borderStrong.a - Config.Appearance.border.a) * validationPulse)
                            : Config.Appearance.border
                        borderWidthOverride: Config.Appearance.borderWidth
                        // invalid alone suffices: WidgetStates.resolve() already
                        // ranks invalid over loading, so adding `loading` would be
                        // a silent no-op. Gated on `!validating` so the previous
                        // attempt's stale error does not paint the field red while
                        // a new attempt is still being verified.
                        invalid: (root.errorText.length > 0 || root.lockedOut) && !root.validating

                        // A short, deliberate shake on every failed attempt,
                        // triggered once per errorText change rather than
                        // continuously, so it never fires on ordinary typing.
                        transform: Translate { id: shakeT; x: 0 }
                        SequentialAnimation {
                            id: shakeAnim
                            loops: 1
                            NumberAnimation { target: shakeT; property: "x"; to: -fieldCell.width * 0.6; duration: 45 }
                            NumberAnimation { target: shakeT; property: "x"; to: fieldCell.width * 0.6; duration: 90 }
                            NumberAnimation { target: shakeT; property: "x"; to: -fieldCell.width * 0.4; duration: 90 }
                            NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 60 }
                        }
                        Connections {
                            target: root
                            function onErrorTextChanged() { if (root.errorText.length > 0) shakeAnim.restart() }
                        }

                        TextInput {
                            id: passwordField
                            width: parent.width
                            enabled: !root.lockedOut
                            // Editing is blocked for the verification only, caret
                            // and border pulsing in step. Typing into an
                            // already-submitted password is noise, and the ~2s
                            // wait is long enough that accepting edits would read
                            // as broken. Scoped to `validating` alone, never to
                            // PAM's conversational state.
                            readOnly: root.validating
                            // A closed tab loop: the field opts into the tab
                            // chain, so Tab cycles field → pills → field (QtQuick
                            // wraps within a FocusScope). Every stop stays
                            // reachable; dropping the power row from the chain
                            // would strand it.
                            activeFocusOnTab: true
                            // Old-terminal input: mono role, solid block caret,
                            // `*` masking — the same bullet the Plymouth prompt
                            // draws, so both auth surfaces read as one.
                            font.family: Config.Appearance.fontMono
                            font.pixelSize: Config.Appearance.fontSize2
                            color: passwordPanel.contentColor
                            passwordCharacter: "*"
                            selectByMouse: false
                            cursorDelegate: Rectangle {
                                width: fieldCell.width
                                height: fieldCell.height
                                color: passwordPanel.contentColor
                                // While `validating` the blink pauses and the
                                // caret pulses 0.35→1 with the border, putting the
                                // verification inside the field, not only on its
                                // edge.
                                opacity: root.validating ? 0.35 + 0.65 * validationPulse : 1.0
                                visible: passwordField.activeFocus && (root.validating || caret.on)
                            }
                            onTextChanged: {
                                caret.on = true
                                if (passwordField.activeFocus)
                                    caretBlink.restart()
                            }
                            // `root.pam.` explicitly: this object lives inside
                            // `surface: Component`, instantiated per screen, so it
                            // crosses a Component boundary where a bare `pam`
                            // would be ambiguous.
                            echoMode: root.pam.responseVisible ? TextInput.Normal : TextInput.Password
                            // Deliberately NOT `enabled:
                            // root.pam.responseRequired`. Gating usability on
                            // PAM's conversation state makes "PAM hasn't asked
                            // yet" and "PAM can never start" look identical — a
                            // dead field either way. The field always accepts
                            // typing; Keys.onReturnPressed guards the thing that
                            // matters, never forwarding a response PAM did not ask
                            // for.

                            Keys.onPressed: (event) => { surface.inputSeen = true; event.accepted = false }
                            Keys.onReturnPressed: {
                                if (!root.lockedOut && root.pam.responseRequired) {
                                    root.pam.respond(text)
                                    // Starts the validating state — the field
                                    // pulses and the line below says "Verifying…"
                                    // until PAM's `completed`/`error` clears it.
                                    root.validating = true
                                }
                                text = ""
                            }
                        }
                    }
                }

                // Lockout drain: while `lockedOut` a hairline under the field
                // drains 1→0 with the 1s countdown, error colour at reduced
                // alpha, each tick eased on category B so it reads continuous.
                // Sits between field and error line and never moves the field.
                Item {
                    id: lockoutBar
                    width: passwordPanel.width
                    height: Math.max(1, Math.round(surface.chWidth * 0.35))
                    visible: root.lockedOut
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * root.lockoutProgress
                        color: Qt.rgba(Config.Appearance.error.r,
                                       Config.Appearance.error.g,
                                       Config.Appearance.error.b, 0.6)
                        Behavior on width {
                            NumberAnimation {
                                duration: Config.Appearance.motionBDuration
                                easing.type: Easing.Bezier
                                easing.bezierCurve: Config.Appearance.motionBCurve
                            }
                        }
                    }
                }

                Widgets.StyledText {
                    id: errorText
                    anchors.horizontalCenter: parent.horizontalCenter
                    // While `validating` this line is the wait's static label
                    // — a neutral "Verifying…" replacing the previous
                    // attempt's stale error, which neither lingers in red nor
                    // vanishes mid-wait.
                    tone: root.validating ? "" : "error"
                    invalid: (root.errorText.length > 0 || root.lockedOut) && !root.validating
                    text: root.validating
                        ? "Verifying…"
                        : (root.lockedOut
                            ? ("Too many attempts — try again in " + root.lockoutRemaining + "s")
                            : (root.errorText.length > 0 ? root.errorText : (root.pam.message.length > 0 ? root.pam.message : " ")))
                }

                // The pill row shared with Dialogs/PowerMenu.qml, minus "lock"
                // — locking an already-locked screen is meaningless. No action
                // is primary, so pills stay bare.
                Item {
                    id: powerBlock
                    width: parent.width
                    height: powerRow.implicitHeight

                    Dialogs.PowerActionsRow {
                        id: powerRow
                        anchors.horizontalCenter: parent.horizontalCenter
                        // Left tab-reachable: the closed loop described on
                        // passwordField is what keeps this safe, not removing
                        // the row from the chain.
                        actions: ["logout", "suspend", "hibernate", "reboot", "shutdown"]
                        onChosen: (action) => surface.choosePower(action)
                    }
                }
            }

            Item {
                id: clockTick
                property var now: new Date()
                Timer {
                    interval: 1000
                    running: true
                    repeat: true
                    onTriggered: clockTick.now = new Date()
                }
            }

            // Safety: if the deferred reveal never runs, do not leave a locked
            // screen with invisible (but focus-holding) content.
            Timer {
                interval: 1200
                running: true
                onTriggered: if (!transition.revealed && !root.authenticated) transition.snap(true)
            }
        }

        // Wiring for the transition LockTransition.qml owns: the conceal
        // starts only from authenticated → Success, and its finished handler
        // is the one place `locked` is cleared.
        Connections {
            target: root
            function onAuthenticatedChanged() {
                if (root.authenticated) {
                    transition.conceal()
                    if (effectLoader.item) effectLoader.item.running = false
                }
            }
        }
        Connections {
            target: transition
            function onConcealFinished() {
                root.locked = false
                // Timed to the conceal finishing, not to authentication
                // succeeding — see Services/LockState.qml's own header.
                Services.LockState.locked = false
            }
        }
        Connections {
            target: root
            function onValidationAttempt(success) { surface._pulseScreensaver(success) }
        }
    }
    }
}