import QtQuick
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets

// The Media popout — the full controls for the active MPRIS player, the
// same shape Status.qml's own smaller "Media control" section uses, plus
// a live elapsed/total readout with a read-only progress bar and the
// connected player's identity. Shows a quiet "No media playing." line
// while no player is connected, so opening the card (from the note glyph)
// is still meaningful feedback instead of an empty panel.

Widgets.StaggerReveal {
    id: root

    property real chWidth: 0
    property bool active: false

    shown: root.active
    width: parent ? parent.width : 0
    spacing: root.chWidth * Config.Appearance.space2
    visible: root.active

    function _fmt(secs) {
        if (isNaN(secs) || secs <= 0) return "0:00"
        const m = Math.floor(secs / 60)
        const s = Math.floor(secs % 60)
        return m + ":" + String(s).padStart(2, "0")
    }

    Widgets.OverlaySection {
        width: parent.width
        Column {
            width: parent.width
            spacing: root.chWidth * Config.Appearance.space1

            Widgets.StyledText {
                width: parent.width
                kind: "label"; sizeStep: 0
                elide: Text.ElideRight
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

            // Elapsed / total + a read-only progress rail. MprisPlayer's
            // own `position` is deliberately non-reactive (quickshell only
            // pushes updates on non-linear changes — track change, seek —
            // to save CPU), so this timer re-reads it once a second while
            // the card is open and imperatively drives the two readouts;
            // `onActiveChanged`/`onCompleted` catch every state change in
            // between.
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
                    // Read-only on purpose: seeking is beyond this card's
                    // scope (a `canSeek` interactive Meter is a small
                    // follow-up once real usage asks for it).
                    interactive: false
                    fillColor: Config.Appearance.accent
                }
            }

            Row {
                spacing: root.chWidth * Config.Appearance.space2
                Widgets.SmallButton {
                    label: "Previous"
                    enabled: Services.Mpris.active !== null && Services.Mpris.active.canGoPrevious
                    onClicked: Services.Mpris.active.previous()
                }
                Widgets.SmallButton {
                    label: (Services.Mpris.active !== null && Services.Mpris.active.isPlaying) ? "Pause" : "Play"
                    enabled: Services.Mpris.active !== null
                        && (Services.Mpris.active.canPlay || Services.Mpris.active.canPause)
                    onClicked: Services.Mpris.active.togglePlaying()
                }
                Widgets.SmallButton {
                    label: "Next"
                    enabled: Services.Mpris.active !== null && Services.Mpris.active.canGoNext
                    onClicked: Services.Mpris.active.next()
                }
            }
        }
    }

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