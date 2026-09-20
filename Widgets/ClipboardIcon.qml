import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// Same dumb/reusable icon family as the rest of Widgets/*Icon —
// Bar/modules/Clipboard.qml owns the Services/Clipboard.qml reads and calls
// `arrived()` for the short scale pop on a new entry, same technique as
// NotificationBellIcon's `dndPop`.
//
// Kept as a real font-symbol glyph rather than hand-drawn: matching
// Bar/glyphs.js's own glyph pixel-for-pixel by hand is unnecessary risk for a
// shape this generic — same judgment BluetoothIcon makes for its own glyph.

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
        // directly; see NotificationBellIcon's identical note for why the two
        // would otherwise fight over the same property.
    }

    SequentialAnimation {
        id: pop
        NumberAnimation { target: glyphText; property: "scale"; to: 1.22
            duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        NumberAnimation { target: glyphText; property: "scale"; to: 1.0
            duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
