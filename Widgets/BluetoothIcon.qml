import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// Same dumb/reusable icon family as the other Widgets/*Icon files
// Bar/modules/Bluetooth.qml owns the state reads. Deliberately NOT a
// from-scratch Canvas redraw of the bluetooth rune the way
// SunMoonIcon/VolumeIcon/BatteryIcon/WifiIcon draw their own shapes: that
// glyph's diagonal strokes are intricate enough that hand-authoring its path
// blind (no compositor access to check the result against) risks a worse
// outcome than the verified font-symbol glyph, rendered as plain Text here
// rather than through Widgets/StyledIcon so this stays self-contained like
// every sibling icon file. What's animated is the new part: `poweredAmount`
// fades the glyph's own opacity between a dimmed "off" look and full "on"
// (category B, a discrete activation event), and a small dot badge in the
// corner breathes continuously (category A same reasoning as
// Widgets/BatteryIcon.qml's charging bolt and Widgets/WifiIcon.qml's search
// pulse) for as long as a device stays connected — an ongoing state, not a
// one-off transition. No glyph-SWAP between off/on/connected shapes: that
// would reintroduce an instant snap between two images. One glyph,
// continuously varying opacity + a badge, sidesteps it entirely.

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
