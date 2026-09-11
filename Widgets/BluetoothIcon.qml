import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/BluetoothIcon (docs/TODO.md, status-bar rework:
// "bluetooth activation"). Same dumb/reusable icon family as the other
// Widgets/*Icon files, Bar/modules/Bluetooth.qml owns the state reads.
//
// Deliberately NOT a from-scratch Canvas redraw of the bluetooth rune
// (the Nordic Hagall+Bjarkan glyph every real bluetooth icon derives
// from) the way SunMoonIcon/VolumeIcon/BatteryIcon/WifiIcon draw their
// own shapes: that glyph's diagonal strokes are intricate enough that
// hand-authoring its path blind (no compositor access to check the
// result against) risks a worse outcome than reusing the one already
// verified this session against nerd-fonts' own glyphnames.json (the
// same Steam-glyph-fix method). So the base shape stays the real
// font-symbol glyph, rendered as plain Text here rather than through
// Widgets/StyledIcon (self-contained, matching every sibling file in
// this icon family) — what's animated is genuinely new: `poweredAmount`
// fades the glyph's own opacity between a dimmed "off" look and full
// "on" (category B, a discrete activation event), and a small dot badge
// in the corner breathes continuously (category A, "tracking feedback...
// continuous", the same reasoning Widgets/BatteryIcon.qml's charging
// bolt and Widgets/WifiIcon.qml's search pulse already use) for as long
// as a device stays connected — an ongoing state, not a one-off
// transition, so it does not belong to category B.
//
// No glyph-SWAP between off/on/connected shapes: that would reintroduce
// exactly the instant-snap-between-two-images problem the user's own
// "crossfade is not enough" directive ruled out for the brightness icon.
// One glyph, continuously varying opacity + a badge, sidesteps it
// entirely rather than working around it.

Item {
    id: root

    property color iconColor: "white"
    property int sizeStep: 2
    property string glyph: ""
    property real poweredAmount: 1.0    // 0..1, category-B Behavior at the call site
    property real connectedAmount: 0.0   // 0..1, category-B Behavior; >0 arms the category-A badge pulse

    readonly property real _fontSize: WidgetStates.fontPixelSize(Config.Appearance, root.sizeStep)
    implicitWidth: glyphText.implicitWidth
    implicitHeight: glyphText.implicitHeight
    width: implicitWidth
    height: implicitHeight

    readonly property real _opacity: 0.3 + 0.7 * Math.max(0, Math.min(1, root.poweredAmount))

    Text {
        id: glyphText
        text: root.glyph
        font.family: Config.Appearance.fontSymbol
        font.pixelSize: root._fontSize
        color: root.iconColor
        opacity: root._opacity
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
    }

    readonly property int _badgeEasing: Config.Appearance.motionAEasing === "linear" ? Easing.Linear : Easing.OutQuad
    property real badgePulse: 0.6
    SequentialAnimation on badgePulse {
        running: root.connectedAmount > 0.001
        loops: Animation.Infinite
        NumberAnimation { to: 1.0; duration: Config.Appearance.motionAPeriod / 2; easing.type: root._badgeEasing }
        NumberAnimation { to: 0.6; duration: Config.Appearance.motionAPeriod / 2; easing.type: root._badgeEasing }
    }

    Rectangle {
        width: Math.max(2, root._fontSize * 0.24)
        height: width
        radius: width / 2
        color: root.iconColor
        opacity: root.connectedAmount * root.badgePulse
        anchors.right: glyphText.right
        anchors.bottom: glyphText.bottom
        anchors.rightMargin: -width * 0.15
        anchors.bottomMargin: -width * 0.15
    }
}
