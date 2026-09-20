import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../../Bar/glyphs.js" as Glyphs
import "../../../Widgets/WidgetStates.js" as WidgetStates

// Media controls shared by Media.qml and Status.qml's media section. Reads
// active MPRIS player; `active` gates progress timer and marquee drift. Source
// line clickable, focuses player window by app id match (desktop entry or
// identity). Best effort; fallback is MPRIS raise().

Column {
    id: root

    property real chWidth: 0
    property bool active: false

    spacing: root.chWidth * Config.Appearance.space2

    function _fmt(secs) {
        if (isNaN(secs) || secs <= 0) return "0:00"
        const m = Math.floor(secs / 60)
        const s = Math.floor(secs % 60)
        return m + ":" + String(s).padStart(2, "0")
    }

    function _can(prop) {
        const p = Services.Mpris.active
        return p !== null && p[prop]
    }

    // Best-effort focus of the player's window, see the header note.
    function _focusSource() {
        const p = Services.Mpris.active
        if (!p) return
        const needles = []
        if (p.desktopEntry && p.desktopEntry.length > 0) needles.push(p.desktopEntry.toLowerCase())
        if (p.identity && p.identity.length > 0) needles.push(p.identity.toLowerCase())
        const model = Services.HyprlandBridge.toplevels
        const values = model ? model.values : null
        if (values) {
            for (let i = 0; i < values.length; i++) {
                const t = values[i]
                // Real app id is .wayland.appId; title is secondary match source.
                const cls = String((t.wayland && t.wayland.appId) || t.title || "").toLowerCase()
                if (cls.length === 0) continue
                for (let j = 0; j < needles.length; j++) {
                    const needle = needles[j]
                    if (cls === needle || cls.indexOf(needle) >= 0 || needle.indexOf(cls) >= 0) {
                        if (t.address && t.address.length > 0) {
                            Services.HyprlandBridge.dispatch(
                                'hl.dsp.focus({ window = "address:' + t.address + '" })')
                            return
                        }
                    }
                }
            }
        }
        // No window match; fallback to MPRIS raise().
        if (p.canRaise) p.raise()
    }

    // --- identity / track info ------------------------------------------

    // Source row clickable; hover brightens text to show it's actionable.
    Item {
        width: parent.width
        implicitHeight: sourceLine.implicitHeight
        Widgets.StyledText {
            id: sourceLine
            width: parent.width
            kind: "label"; sizeStep: 0
            elide: Text.ElideRight
            color: srcHover.hovered ? Config.Appearance.textPrimary : Config.Appearance.textMuted
            text: Services.Mpris.active && Services.Mpris.active.identity.length > 0
                ? Services.Mpris.active.identity : ""
        }
        HoverHandler { id: srcHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root._focusSource() }
    }
    // Track title and artist—album lines marquee when they don't fit
    // (Widgets/MarqueeText.qml); `running` follows the card gate so the drift
    // never ticks while the card is closed.
    Widgets.MarqueeText {
        width: parent.width
        kind: "title"; sizeStep: 0
        running: root.active
        text: Services.Mpris.active && Services.Mpris.active.trackTitle.length > 0
            ? Services.Mpris.active.trackTitle : "No media playing."
    }
    Widgets.MarqueeText {
        width: parent.width
        kind: "label"; sizeStep: 0
        running: root.active
        text: Services.Mpris.active
            ? (Services.Mpris.active.trackArtist
                + (Services.Mpris.active.trackAlbum.length > 0
                    ? " — " + Services.Mpris.active.trackAlbum : ""))
            : ""
    }

    // --- elapsed / total + read-only progress rail ----------------------

    // MprisPlayer's own `position` is deliberately non-reactive (quickshell
    // only pushes updates on non-linear changes — track change, seek — to save
    // CPU), so this timer re-reads it once a second while the card is open and
    // imperatively drives the two readouts; `onActiveChanged` / `onCompleted`
    // catch every state change in between.
    Item {
        width: parent.width
        implicitHeight: Math.max(posBar.implicitHeight, posTimes.implicitHeight)
        Widgets.StyledText {
            id: posTimes
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            mono: true; kind: "label"; sizeStep: 0
            text: root._fmt(posBar.value * (Services.Mpris.active ? Services.Mpris.active.length : 0))
                + " / " + root._fmt(Services.Mpris.active ? Services.Mpris.active.length : 0)
        }
        Widgets.Meter {
            id: posBar
            anchors.left: parent.left
            anchors.right: posTimes.left
            anchors.rightMargin: root.chWidth * Config.Appearance.space2
            anchors.verticalCenter: parent.verticalCenter
            // Read-only on purpose: seeking is beyond this card's scope (a
            // `canSeek` interactive Meter is a small follow-up once real usage
            // asks for it).
            interactive: false
            fillColor: Config.Appearance.accent
        }
    }

    // --- transport: shuffle / prev-play-pause-next / repeat -------------

    // One row so every glyph sits on the same centre line, bound with a wider
    // gap (space3) between the outboard shuffle/repeat and the transport trio
    // (space2) — the separation that keeps the "what to play next" controls
    // apart from the queue-state toggles. Every button is 5 ch tall, the
    // play/pause target, so no neighbour reads as vertically off-line beside
    // it. Shuffle and repeat appear only when the active player supports them
    // ("if available") and are hidden otherwise; the row then centres what
    // remains. IconButton has no disabled/active look of its own, so each
    // button gates the click at the signal, fades to the shared inactive ratio
    // while disabled, and paints accent while its queue state is on.
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.chWidth * Config.Appearance.space3

        Widgets.IconButton {
            id: shuffleBtn
            width: root.chWidth * 4
            height: root.chWidth * 5
            glyph: Glyphs.shuffle
            sizeStep: 2
            visible: root._can("shuffleSupported")
            enabled: root._can("shuffleSupported") && root._can("canControl")
            color: Services.Mpris.active !== null && Services.Mpris.active.shuffle
                ? Config.Appearance.accent : Config.Appearance.textMuted
            hoverColor: Services.Mpris.active !== null && Services.Mpris.active.shuffle
                ? Config.Appearance.accent : Config.Appearance.textPrimary
            opacity: shuffleBtn.enabled ? 1 : WidgetStates.INACTIVE_OPACITY
            Behavior on opacity {
                NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
            onActivated: {
                const p = Services.Mpris.active
                if (p !== null && shuffleBtn.enabled) p.shuffle = !p.shuffle
            }
        }

        // The transport trio, bound tighter than the outboard toggles.
        Row {
            spacing: root.chWidth * Config.Appearance.space2
            Widgets.IconButton {
                id: prevBtn
                width: root.chWidth * 4
                height: root.chWidth * 5
                glyph: Glyphs.skipPrev
                sizeStep: 2
                enabled: root._can("canGoPrevious")
                opacity: prevBtn.enabled ? 1 : WidgetStates.INACTIVE_OPACITY
                Behavior on opacity {
                    NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                }
                onActivated: { if (prevBtn.enabled) Services.Mpris.active.previous() }
            }
            Widgets.IconButton {
                id: playBtn
                width: root.chWidth * 5
                height: root.chWidth * 5
                // Action-style, unlike the bar glyph (which shows the current
                // state): here the icon is "what this press does" — pause
                // while playing, play while paused.
                glyph: Services.Mpris.active !== null && Services.Mpris.active.isPlaying
                    ? Glyphs.pause : Glyphs.play
                sizeStep: 3
                enabled: root._can("canPlay") || root._can("canPause")
                opacity: playBtn.enabled ? 1 : WidgetStates.INACTIVE_OPACITY
                Behavior on opacity {
                    NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                }
                onActivated: { if (playBtn.enabled && Services.Mpris.active !== null) Services.Mpris.active.togglePlaying() }
            }
            Widgets.IconButton {
                id: nextBtn
                width: root.chWidth * 4
                height: root.chWidth * 5
                glyph: Glyphs.skipNext
                sizeStep: 2
                enabled: root._can("canGoNext")
                opacity: nextBtn.enabled ? 1 : WidgetStates.INACTIVE_OPACITY
                Behavior on opacity {
                    NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
                }
                onActivated: { if (nextBtn.enabled) Services.Mpris.active.next() }
            }
        }

        Widgets.IconButton {
            id: repeatBtn
            width: root.chWidth * 4
            height: root.chWidth * 5
            // repeat-once while looping a single track, plain repeat
            // otherwise; accent while any loop state is active.
            glyph: Services.Mpris.active !== null && Services.Mpris.active.loopState === Services.Mpris.loopStateTrack
                ? Glyphs.repeatOnce : Glyphs.repeat
            sizeStep: 2
            visible: root._can("loopSupported")
            enabled: root._can("loopSupported") && root._can("canControl")
            color: Services.Mpris.active !== null && Services.Mpris.active.loopState !== Services.Mpris.loopStateNone
                ? Config.Appearance.accent : Config.Appearance.textMuted
            hoverColor: Services.Mpris.active !== null && Services.Mpris.active.loopState !== Services.Mpris.loopStateNone
                ? Config.Appearance.accent : Config.Appearance.textPrimary
            opacity: repeatBtn.enabled ? 1 : WidgetStates.INACTIVE_OPACITY
            Behavior on opacity {
                NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
            }
            // Off → Playlist ("repeat all") → Track ("repeat one") → Off the
            // same cycle reference players use.
            onActivated: {
                const p = Services.Mpris.active
                if (!repeatBtn.enabled || p === null) return
                p.loopState = p.loopState === Services.Mpris.loopStateNone
                    ? Services.Mpris.loopStatePlaylist
                    : p.loopState === Services.Mpris.loopStatePlaylist
                        ? Services.Mpris.loopStateTrack
                        : Services.Mpris.loopStateNone
            }
        }
    }

    // --- position tick ---------------------------------------------------

    Timer {
        id: posTick
        interval: 1000
        running: root.active && Services.Mpris.active !== null
        repeat: true
        onTriggered: root._syncPos()
    }
    function _syncPos() {
        const p = Services.Mpris.active
        posBar.value = p !== null ? p.position / Math.max(1, p.length) : 0
    }
    onActiveChanged: root._syncPos()
    Component.onCompleted: root._syncPos()
}