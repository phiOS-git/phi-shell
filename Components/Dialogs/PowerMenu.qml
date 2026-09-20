import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Config as Config
import qs.Services as Services
import qs.Widgets as Widgets
import "." as Local

// Services/PowerMenu.qml owns the shown/double-tap state — this file is
// presentation only. Layer-shell/scrim/fade plumbing copied verbatim from
// Components/Dialogs/ConfirmDialog.qml.
// A bare horizontal PowerActionsRow pill row directly on the scrim.
// Reboot/shutdown still go through the existing Services.ConfirmDialog
// "this cannot be undone" step (Services.PowerActions.needsConfirm())
// PowerActionsRow's own `chosen` signal only decides whether to interpose
// that step, the mechanism itself is untouched.
// `pills.focusFirst()` runs every time this overlay actually becomes
// shown, not just once at startup — this window is created once and only
// ever shown/hidden via opacity (never destroyed), so
// Component.onCompleted alone would only catch the very first SUPER+L of
// the session.
PanelWindow {
    id: root

    readonly property bool shown: Services.PowerMenu.shown

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    visible: root.shown || fadeRoot.opacity > 0
    onShownChanged: if (root.shown) Qt.callLater(() => pills.focusFirst())

    Component.onCompleted: {
        if (root.WlrLayershell) root.WlrLayershell.layer = WlrLayer.Overlay
    }

    Services.LayerFocus { target: root }

    Widgets.Scrim {
        anchors.fill: parent
        shown: root.shown
        // Same reasoning as ConfirmDialog's own strong scrim — a menu of
        // session-ending actions (including shutdown/reboot) is the same
        // weight of full-attention blocking surface.
        strong: true
    }
    // A second identical scrim layer stacked on the first: this overlay
    // sits on top of the real, likely bright desktop — windows, terminals
    // whatever was on screen — so `strong` alone (80% black, the darkest
    // existing token) still lets more of it show through than wanted.
    // Two 80%-opaque layers stack to ~96% transmittance, reusing the
    // existing token twice rather than inventing a new one-off opacity
    // value. No blur effect is available here (would need a Qt
    // graphical-effects module this codebase doesn't depend on) — this is
    // the lever design tokens allow.
    Widgets.Scrim {
        anchors.fill: parent
        shown: root.shown
        strong: true
    }

    function _confirmAndPerform(action) {
        Services.ConfirmDialog.open({
            title: Services.PowerActions.title(action),
            message: "This cannot be undone.",
            confirmLabel: Services.PowerActions.title(action),
            onConfirm: () => Services.PowerActions.perform(action)
        })
        Services.PowerMenu.hide()
    }
    function _choose(action) {
        if (Services.PowerActions.needsConfirm(action)) root._confirmAndPerform(action)
        else { Services.PowerActions.perform(action); Services.PowerMenu.hide() }
    }

    Item {
        id: fadeRoot
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Config.Appearance.motionBDuration; easing.type: Easing.Bezier; easing.bezierCurve: Config.Appearance.motionBCurve }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Services.PowerMenu.hide()
        }

        // Swallow clicks on the row itself so tapping a pill doesn't also
        // hit this Item's own click-outside-closes MouseArea above.
        Item {
            anchors.centerIn: parent
            width: pills.implicitWidth
            height: pills.implicitHeight

            MouseArea { anchors.fill: parent }

            focus: root.shown
            Keys.onEscapePressed: Services.PowerMenu.hide()

            Local.PowerActionsRow {
                id: pills
                actions: ["lock", "logout", "suspend", "hibernate", "reboot", "shutdown"]
                onChosen: (action) => root._choose(action)
            }
        }
    }
}
