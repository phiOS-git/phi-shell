import QtQuick
import qs.Config as Config
import "WidgetStates.js" as WidgetStates

// phiOS — Widgets/NetworkIcon (docs/TODO.md, status-bar rework follow-up:
// the user's "all other icons" directive, applied to Bar/modules/Network.qml
// — the Tailscale/VPN "on/off" glyph that used to be a static `glyph:`
// swap between Glyphs.vpn and Glyphs.vpnOff). Same dumb/reusable icon
// family as the rest of Widgets/*Icon — Bar/modules/Network.qml owns the
// Services.Tailscale/Services.Vpn reads.
//
// Same technique as Widgets/NotificationBellIcon's bell/bell-off: two
// overlaid glyphs cross-faded by `activeAmount`, plus a small scale pop on
// the transition, rather than a two-branch static `glyph:` snap. Kept as
// real font-symbol glyphs (not hand-drawn) for the same reason
// BluetoothIcon does — the vpn/network-off runes are intricate enough to
// risk a worse result drawn blind.
//
// No separate ts/vpn badge dots: unlike bluetooth's connected-badge (which
// adds information the base glyph doesn't carry), Bar/modules/Network.qml
// already renders which of Tailscale/VPN is up in its own label text
// ("<hostname> | <tunnel>") — a second badge here would duplicate that
// without adding anything, which is exactly the clutter the bluetooth/
// wifi icons deliberately avoided by staying single-signal.

Item {
    id: root

    property color iconColor: "white"
    property int sizeStep: 2
    property real activeAmount: 0.0 // 0..1, category-B Behavior at the call site

    readonly property real _fontSize: WidgetStates.fontPixelSize(Config.Appearance, root.sizeStep)
    implicitWidth: Math.max(onGlyph.implicitWidth, offGlyph.implicitWidth)
    implicitHeight: Math.max(onGlyph.implicitHeight, offGlyph.implicitHeight)
    width: implicitWidth
    height: implicitHeight

    // Not `onGlyphText`/`offGlyphText`: a property name starting with "on"
    // followed by an uppercase letter is exactly QML's signal-handler
    // naming convention (`onFooChanged`) — a real property named that way
    // still works, but it is the same class of naming footgun already
    // caught twice this session (underscore-prefixed properties needing
    // their own `onXChanged`), not worth risking a third time.
    property string glyphActive: ""
    property string glyphInactive: ""

    Item {
        id: pivot
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.implicitWidth
        height: root.implicitHeight

        Text {
            id: offGlyph
            text: root.glyphInactive
            font.family: Config.Appearance.fontSymbol
            font.pixelSize: root._fontSize
            color: root.iconColor
            opacity: 1 - root.activeAmount
            anchors.centerIn: parent
        }
        Text {
            id: onGlyph
            text: root.glyphActive
            font.family: Config.Appearance.fontSymbol
            font.pixelSize: root._fontSize
            color: root.iconColor
            opacity: root.activeAmount
            anchors.centerIn: parent
        }

        scale: 1.0
        // No `Behavior on scale`, deliberately — see NotificationBellIcon's
        // identical note: `pop` below already drives `scale` directly, and
        // stacking a Behavior on top would fight it for the same property.
    }

    // Triggered by an exposed function, called once by the caller's own
    // discrete `onAnyActiveChanged` — NOT by `onActiveAmountChanged` here:
    // activeAmount arrives wrapped in the caller's category-B Behavior,
    // which reassigns it on every animation frame of its ~120ms ramp (see
    // NotificationBellIcon.dndToggled's identical note — same bug class,
    // same fix).
    function toggled() { pop.restart() }
    SequentialAnimation {
        id: pop
        NumberAnimation { target: pivot; property: "scale"; to: 1.12
            duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        NumberAnimation { target: pivot; property: "scale"; to: 1.0
            duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
    }
}
