import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "../../Bar/glyphs.js" as Glyphs
import "../../../Widgets/WidgetStates.js" as WidgetStates

// The media controls body shared by BarPopout/modules/Media.qml (the full
// popout card) and BarPopout/modules/Status.qml's "Media control" section —
// the same inner section in both cards so future layout changes happen here
// once. Reads the active MPRIS player from Services.Mpris; `active` is
// driven by the consuming card so the one-second progress timer only runs
// while the card is actually on screen.

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

    // --- identity / track info ------------------------------------------

    Widgets.StyledText {
        width: parent.width
        kind: "label"; sizeStep: 0
        elide: Text.ElideRight
        color: Config.Appearance.textMuted
        text: Services.Mpris.active && Services.Mpris.active.identity.length > 0
            ? Services.Mpris.active.identity : ""
    }
    Widgets.StyledText {
        width: parent.width
        kind: "title"; sizeStep: 0
        elide: Text.ElideRight
        text: Services.Mpris.active && Services.Mpris.active.trackTitle.length > 0
            ? Services.Mpris.active.trackTitle : "No media playing."
    }
    Widgets.StyledText {
        width: parent.width
        kind: "label"; sizeStep: 0
        elide: Text.ElideRight
        text: Services.Mpris.active
            ? (Services.Mpris.active.trackArtist
                + (Services.Mpris.active.trackAlbum.length > 0
                    ? " — " + Services.Mpris.active.trackAlbum : ""))
            : ""
    }

    // --- elapsed / total + read-only progress rail ----------------------

    // MprisPlayer's own `position` is deliberately non-reactive (quickshell
    // only pushes updates on non-linear changes — track change, seek — to
    // save CPU), so this timer re-reads it once a second while the card is
    // open and imperatively drives the two readouts; `onActiveChanged` /
    // `onCompleted` catch every state change in between.
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
            // Read-only on purpose: seeking is beyond this card's scope
            // (a `canSeek` interactive Meter is a small follow-up once
            // real usage asks for it).
            interactive: false
            fillColor: Config.Appearance.accent
        }
    }

    // --- transport: glyph buttons ----------------------------------------

    // Three icon buttons, prev / play-pause / next, centred. Bigger than
    // a bare glyph (explicit ch-based touch target) with the play/pause
    // keyed slightly larger. IconButton has no built-in disabled look, so
    // each fades to the shared inactive ratio and gates the click at the
    // signal.
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.chWidth * Config.Appearance.space2
        Widgets.IconButton {
            id: prevBtn
            width: root.chWidth * 4
            height: root.chWidth * 4
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
            height: root.chWidth * 4
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
