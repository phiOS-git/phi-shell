import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/ClipboardIcon (docs/TODO.md, status-bar rework follow-up:
// the user's "all other icons" directive, applied to Bar/modules/
// Clipboard.qml). Same dumb/reusable icon family as the rest of
// Widgets/*Icon — Bar/modules/Clipboard.qml owns the Services/Clipboard.qml
// reads.
//
// Bar/modules/Clipboard.qml already had a real, working "new entry"
// signal — a `tone: "info"` pulse via Segment's own colour Behavior, added
// earlier this session. That stays (it is not broken, nothing here
// replaces it); what this file adds is the SHAPE-level motion the rest of
// this rework's icons all got and the clipboard glyph did not yet: a
// short scale pop on arrival, same technique as NotificationBellIcon's
// `dndPop` / NetworkIcon's `pop` — call `arrived()` once per new entry.
//
// Kept as a real font-symbol glyph (not hand-drawn): a clipboard is a
// simple rectangle in principle, but matching Bar/glyphs.js's own glyph
// pixel-for-pixel by hand is unnecessary risk for a shape this generic —
// same judgment BluetoothIcon documents for its own glyph.

Item {
    id: root

    property color iconColor: "white"
    property int sizeStep: 2
    property string glyph: ""

    readonly property real _fontSize: WidgetStates.fontPixelSize(Config.Appearance, root.sizeStep)
    implicitWidth: glyphText.implicitWidth
    implicitHeight: glyphText.implicitHeight
    width: implicitWidth
    height: implicitHeight

    function arrived() { pop.restart() }

    Text {
        id: glyphText
        text: root.glyph
        font.family: Config.Appearance.fontSymbol
        font.pixelSize: root._fontSize
        color: root.iconColor
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        scale: 1.0
        // No `Behavior on scale`, deliberately — `pop` below drives it
        // directly; see NotificationBellIcon's identical note for why the
        // two would otherwise fight over the same property.
    }

    SequentialAnimation {
        id: pop
        NumberAnimation { target: glyphText; property: "scale"; to: 1.22
            duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        NumberAnimation { target: glyphText; property: "scale"; to: 1.0
            duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
